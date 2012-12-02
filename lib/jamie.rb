# -*- encoding: utf-8 -*-

require 'hashie/dash'
require 'mixlib/shellout'
require 'yaml'

require "jamie/version"

module Jamie
  class Platform < Hashie::Dash
    property :name, :required => true
    property :backend_plugin
    property :vagrant_box
    property :vagrant_box_url
    property :base_run_list, :default => []
  end

  class Suite < Hashie::Dash
    property :name, :required => true
    property :run_list, :required => true
    property :json, :default => Hash.new
  end

  class Instance
    attr_reader :suite
    attr_reader :platform
    attr_reader :backend

    def initialize(suite, platform, backend)
      @suite = suite
      @platform = platform
      @backend = backend
    end

    def name
      "#{suite.name}-#{platform.name}".gsub(/_/, '-').gsub(/\./, '')
    end

    def create
      puts "-----> Creating instance #{name}"
      backend.create(self)
      puts "       Creation of instance #{name} complete."
      self
    end

    def converge
      puts "-----> Converging instance #{name}"
      backend.converge(self)
      puts "       Convergence of instance #{name} complete."
      self
    end

    def verify
      puts "-----> Verifying instance #{name}"
      backend.verify(self)
      puts "       Verification of instance #{name} complete."
      self
    end

    def destroy
      puts "-----> Destroying instance #{name}"
      backend.destroy(self)
      puts "       Destruction of instance #{name} complete."
      self
    end

    def test
      puts "-----> Cleaning up any prior instances of #{name}"
      destroy
      puts "-----> Testing instance #{name}"
      create
      converge
      verify
      puts "       Testing of instance #{name} complete."
      self
    end
  end

  class Config
    attr_writer :yaml_file
    attr_writer :platforms
    attr_writer :suites
    attr_writer :log_level
    attr_writer :data_bags_base_path

    DEFAULT_YAML_FILE = File.join(Dir.pwd, '.jamie.yml')
    DEFAULT_LOG_LEVEL = :info
    DEFAULT_BACKEND_PLUGIN = "vagrant"
    DEFAULT_DATA_BAGS_BASE_PATH = File.join(Dir.pwd, 'test/integration')

    def platforms
      @platforms ||= Array(yaml["platforms"]).map { |hash| Platform.new(hash) }
    end

    def suites
      @suites ||= Array(yaml["suites"]).map { |hash| Suite.new(hash) }
    end

    def instances
      @instances ||= begin
        arr = []
        suites.each do |suite|
          platforms.each do |platform|
            plugin = platform.backend_plugin || yaml["backend_plugin"] ||
              DEFAULT_BACKEND_PLUGIN
            arr << Instance.new(suite, platform, Backend.for_plugin(plugin))
          end
        end
        arr
      end
    end

    def yaml_file
      @yaml_file ||= DEFAULT_YAML_FILE
    end

    def log_level
      @log_level ||= DEFAULT_LOG_LEVEL
    end

    def data_bags_base_path
      @data_bags_path ||= DEFAULT_DATA_BAGS_BASE_PATH
    end

    private

    def yaml
      @yaml ||= YAML.load_file(File.expand_path(yaml_file))
    end
  end

  module Backend
    class CommandFailed < StandardError ; end

    def self.for_plugin(plugin)
      klass = self.const_get(plugin.capitalize)
      klass.new
    end

    class Base
      def create(instance)
        raise NotImplementedError, "Subclass must implement"
      end

      def converge(instance)
        raise NotImplementedError, "Subclass must implement"
      end

      def verify(instance)
        # Subclass may choose to implement
        puts "       Nothing to do!"
      end

      def destroy(instance)
        raise NotImplementedError, "Subclass must implement"
      end
    end

    class Vagrant < Jamie::Backend::Base
      def create(instance)
        run "vagrant up #{instance.name} --no-provision"
      end

      def converge(instance)
        run "vagrant provision #{instance.name}"
      end

      def destroy(instance)
        run "vagrant destroy #{instance.name} -f"
      end

      private

      def run(cmd)
        puts "       [vagrant command] '#{cmd}'"
        shellout = Mixlib::ShellOut.new(
          cmd, :live_stream => STDOUT, :timeout => 60000
        )
        shellout.run_command
        puts "       [vagrant command] '#{cmd}' ran " +
          "in #{shellout.execution_time} seconds."
        shellout.error!
      rescue Mixlib::ShellOut::ShellCommandFailed => ex
        raise CommandFailed, ex.message
      end
    end
  end
end