require "steno"
require "optparse"
require "vcap/uaa_util"
require "cf_message_bus/message_bus"
require "cf/registrar"
require "loggregator_emitter"
require "loggregator"
require "cloud_controller/varz"

require_relative "seeds"
require_relative "message_bus_configurer"

module VCAP::CloudController
  class Runner
    attr_reader :config_file, :insert_seed_data

    def initialize(argv)
      @argv = argv

      # default to production. this may be overriden during opts parsing
      ENV["RACK_ENV"] ||= "production"

      @config_file = File.expand_path("../../../config/cloud_controller.yml", __FILE__)
      parse_options!
      parse_config

      @log_counter = Steno::Sink::Counter.new
    end

    def logger
      @logger ||= Steno.logger("cc.runner")
    end

    def options_parser
      @parser ||= OptionParser.new do |opts|
        opts.on("-c", "--config [ARG]", "Configuration File") do |opt|
          @config_file = opt
        end

        opts.on("-m", "--run-migrations", "Actually it means insert seed data") do
          deprecation_warning "Deprecated: Use -s or --insert-seed flag"
          @insert_seed_data = true
        end

        opts.on("-s", "--insert-seed", "Insert seed data") do
          @insert_seed_data = true
        end
      end
    end

    def deprecation_warning(message)
      puts message
    end

    def parse_options!
      options_parser.parse! @argv
    rescue
      puts options_parser
      exit 1
    end

    def parse_config
      @config = Config.from_file(@config_file)
    rescue Membrane::SchemaValidationError => ve
      puts "ERROR: There was a problem validating the supplied config: #{ve}"
      exit 1
    rescue => e
      puts "ERROR: Failed loading config from file '#{@config_file}': #{e}"
      exit 1
    end

    def create_pidfile
      pid_file = VCAP::PidFile.new(@config[:pid_filename])
      pid_file.unlink_at_exit
    rescue
      puts "ERROR: Can't create pid file #{@config[:pid_filename]}"
      exit 1
    end

    def setup_logging
      steno_config = Steno::Config.to_config_hash(@config[:logging])
      steno_config[:context] = Steno::Context::ThreadLocal.new
      steno_config[:sinks] << @log_counter
      Steno.init(Steno::Config.new(steno_config))
    end

    def setup_db
      logger.info "db config #{@config[:db]}"
      db_logger = Steno.logger("cc.db")
      DB.load_models(@config[:db], db_logger)
    end

    def setup_loggregator_emitter
      if @config[:loggregator] && @config[:loggregator][:router] && @config[:loggregator][:shared_secret]
        Loggregator.emitter = LoggregatorEmitter::Emitter.new(@config[:loggregator][:router], "API", @config[:index], @config[:loggregator][:shared_secret])
      end
    end

    def development_mode?
      @config[:development_mode]
    end

    def run!
      EM.run do
        config = @config.dup

        message_bus = MessageBus::Configurer.new(
          :servers => config[:message_bus_servers],
          :logger => logger).go

        start_cloud_controller(message_bus)

        Seeds.write_seed_data(config) if @insert_seed_data

        app = build_rack_app(config, message_bus, development_mode?)

        start_thin_server(app, config)

        router_registrar.register_with_router

        VCAP::CloudController::Varz.bump_user_count

        EM.add_periodic_timer(@config[:varz_update_user_count_period_in_seconds] || 30) do
          VCAP::CloudController::Varz.bump_user_count
        end
      end
    end

    def trap_signals
      %w(TERM INT QUIT).each do |signal|
        trap(signal) do
          logger.warn("Caught signal #{signal}")
          stop!
        end
      end
    end

    def stop!
      logger.info("Unregistering routes.")

      router_registrar.shutdown do
        stop_thin_server
        EM.stop
      end
    end

    def merge_vcap_config
      services = JSON.parse(ENV["VCAP_SERVICES"])
      pg_key = services.keys.select { |svc| svc =~ /postgres/i }.first
      c = services[pg_key].first["credentials"]
      @config[:db][:database] = "postgres://#{c["user"]}:#{c["password"]}@#{c["hostname"]}:#{c["port"]}/#{c["name"]}"
      @config[:port] = ENV["VCAP_APP_PORT"].to_i
    end

    private

    def start_cloud_controller(message_bus)
      create_pidfile

      setup_logging
      setup_db
      Config.configure_components(@config)
      setup_loggregator_emitter

      @config[:bind_address] = VCAP.local_ip(@config[:local_route])
      Config.configure_components_depending_on_message_bus(message_bus)
    end

    def build_rack_app(config, message_bus, development)
      token_decoder = VCAP::UaaTokenDecoder.new(config[:uaa])
      register_with_collector(message_bus)

      Rack::Builder.new do
        use Rack::CommonLogger

        if development
          require 'new_relic/rack/developer_mode'
          use NewRelic::Rack::DeveloperMode
        end

        DeaClient.run
        AppObserver.run

        LegacyBulk.register_subscription

        VCAP::CloudController.health_manager_respondent = HealthManagerRespondent.new(DeaClient, message_bus)
        VCAP::CloudController.health_manager_respondent.handle_requests

        HM9000Respondent.new(DeaClient, message_bus, config[:hm9000_noop]).handle_requests

        VCAP::CloudController.dea_respondent = DeaRespondent.new(message_bus)

        VCAP::CloudController.dea_respondent.start

        map "/" do
          run Controller.new(config, token_decoder)
        end
      end
    end

    def start_thin_server(app, config)
      if @config[:nginx][:use_nginx]
        @thin_server = Thin::Server.new(
            config[:nginx][:instance_socket],
            :signals => false
        )
      else
        @thin_server = Thin::Server.new(@config[:bind_address], @config[:port])
      end

      @thin_server.app = app
      trap_signals

      # The routers proxying to us handle killing inactive connections.
      # Set an upper limit just to be safe.
      @thin_server.timeout = 15 * 60 # 15 min
      @thin_server.threaded = true
      @thin_server.start!
    end

    def stop_thin_server
      @thin_server.stop if @thin_server
    end

    def router_registrar
      @registrar ||= Cf::Registrar.new(
          message_bus_servers: @config[:message_bus_servers],
          host: @config[:bind_address],
          port: @config[:port],
          uri: @config[:external_domain],
          tags: {:component => "CloudController"},
          index: @config[:index],
      )
    end

    def register_with_collector(message_bus)
      VCAP::Component.register(
          :type => 'CloudController',
          :host => @config[:bind_address],
          :port => @config[:varz_port],
          :user => @config[:varz_user],
          :password => @config[:varz_password],
          :index => @config[:index],
          :config => @config,
          :nats => message_bus,
          :logger => logger,
          :log_counter => @log_counter
      )
    end
  end
end
