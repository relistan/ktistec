require "kemal"
require "sqlite3"
require "uri"

module Ktistec
  def self.db_file
    @@db_file ||=
      if Kemal.config.env == "production"
        "sqlite3://#{File.expand_path("~/.ktistec.db", home: true)}"
      else
        "sqlite3://ktistec.db"
      end
  end

  @@database : DB::Database?

  def self.database
    @@database ||= begin
      unless File.exists?(Ktistec.db_file.split("//").last)
        DB.open(Ktistec.db_file) do |db|
          db.exec "CREATE TABLE options (key TEXT PRIMARY KEY, value TEXT)"
          db.exec "INSERT INTO options (key, value) VALUES (?, ?)", "secret_key", Random::Secure.hex(64)
          db.exec "CREATE TABLE migrations (id INTEGER PRIMARY KEY, name TEXT)"
        end
      end
      DB.open(Ktistec.db_file)
    end
  end

  @@secret_key : String?

  def self.secret_key
    @@secret_key ||= Ktistec.database.scalar("SELECT value FROM options WHERE key = ?", "secret_key").as(String)
  end

  # Model-like class for managing settings.
  #
  class Settings
    property host : String?
    property site : String?
    property footer : String?

    getter errors = Hash(String, Array(String)).new

    def initialize
      values =
        Ktistec.database.query_all("SELECT key, value FROM options", as: {String, String?}).reduce(Hash(String, String?).new) do |values, (key, value)|
          values[key] = value
          values
        end
      assign(values)
    end

    def save
      raise "invalid settings" unless valid?
      {"host" => @host, "site" => @site, "footer" => @footer}.each do |key, value|
        Ktistec.database.exec("INSERT OR REPLACE INTO options (key, value) VALUES (?, ?)", key, value)
      end
      self
    end

    def assign(options)
      @host = options["host"] if options.has_key?("host")
      @site = options["site"] if options.has_key?("site")
      @footer = options["footer"] if options.has_key?("footer")
      self
    end

    def valid?
      errors.clear
      host_errors = [] of String
      if (host = @host) && !host.empty?
        uri = URI.parse(host)
        # `URI.parse` treats something like "ktistec.com" as a path
        # name and not a host name. users expectations differ.
        if !present?(uri.host) && present?(uri.path)
          parts = uri.path.split('/', 2)
          unless parts.first.blank?
            uri.host = parts.first
            uri.path = parts.fetch(1, "")
          end
        end
        host_errors << "must have a scheme" unless present?(uri.scheme)
        host_errors << "must have a host name" unless present?(uri.host)
        host_errors << "must not have a fragment" if present?(uri.fragment)
        host_errors << "must not have a query" if present?(uri.query)
        host_errors << "must not have a path" if present?(uri.path) && uri.path != "/"
        if host_errors.empty? && uri.path == "/"
          uri.path = ""
          @host = uri.normalize.to_s
        end
      else
        host_errors << "name must be present"
      end
      errors["host"] = host_errors unless host_errors.empty?
      errors["site"] = ["name must be present"] unless present?(@site)
      errors.empty?
    end

    private def present?(value)
      !value.nil? && !value.empty?
    end
  end

  def self.settings
    # return a new instance if the old instance had validation errors
    @@settings =
      begin
        settings = @@settings
        settings.nil? || !settings.errors.empty? ? Settings.new : settings
      end
  end

  def self.host
    settings.host.not_nil!
  end

  def self.site
    settings.site.not_nil!
  end

  def self.footer
    settings.footer.not_nil!
  end

  # An [ActivityPub](https://www.w3.org/TR/activitypub/) server.
  #
  #     Ktistec::Server.run do
  #       # configuration, initialization, etc.
  #     end
  #
  class Server
    def self.run
      Ktistec::Database.all_pending_versions.each do |version|
        puts Ktistec::Database.do_operation(:apply, version)
      end
      with new yield
      Kemal.run
    end
  end

  # :nodoc:
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
