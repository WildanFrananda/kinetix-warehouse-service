# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kinetix::DatabaseOutage do
  self.use_transactional_tests = false

  let(:live) { ActiveRecord::Base.connection_db_config.configuration_hash }

  def error_from
    yield
    raise "expected the block to raise"
  rescue StandardError => e
    e
  end

  def wrapped(pg_error)
    error_from do
      raise pg_error, "server said no"
    rescue PG::Error
      raise ActiveRecord::StatementInvalid, "#{pg_error}: server said no"
    end
  end

  def separate_pool(**config)
    model = Class.new(ActiveRecord::Base) { self.abstract_class = true }
    stub_const("OutageProbeRecord", model)
    model.establish_connection(live.merge(config))
    model
  end

  it "explains a database nobody answers on" do
    record = separate_pool(host: "127.0.0.1", port: 1)

    expect(described_class.explains?(error_from { record.connection.select_value("SELECT 1") })).to be(true)
  ensure
    record&.remove_connection
  end

  it "explains a connection the server closed under a write" do
    record = separate_pool
    connection = record.connection
    pid = connection.select_value("SELECT pg_backend_pid()")
    ActiveRecord::Base.connection.select_value("SELECT pg_terminate_backend(#{pid})")
    sleep 0.2

    error = error_from { connection.execute("CREATE TEMPORARY TABLE outage_probe (id integer)") }

    expect(error).to be_a(ActiveRecord::ConnectionFailed)
    expect(described_class.explains?(error)).to be(true)
  ensure
    record&.remove_connection
  end

  it "explains a pool with no connection left to lend" do
    record = separate_pool(pool: 1, checkout_timeout: 0.1)
    held = Queue.new
    release = Queue.new
    holder = Thread.new do
      record.connection_pool.with_connection do
        held << true
        release.pop
      end
    end
    held.pop

    error = error_from { record.connection_pool.checkout }
    release << true
    holder.join

    expect(error).to be_a(ActiveRecord::ConnectionTimeoutError)
    expect(described_class.explains?(error)).to be(true)
  ensure
    record&.remove_connection
  end

  [
    PG::TooManyConnections,
    PG::AdminShutdown,
    PG::CrashShutdown,
    PG::CannotConnectNow,
    PG::ConnectionException,
    PG::ConnectionFailure,
    PG::ConnectionBad,
    PG::UnableToSend
  ].each do |pg_error|
    it "explains a statement that failed with #{pg_error}" do
      expect(described_class.explains?(wrapped(pg_error))).to be(true)
    end
  end

  it "does not explain a query the database answered with an error" do
    error = error_from { ActiveRecord::Base.connection.select_value("SELECT 1 / 0") }

    expect(error).to be_a(ActiveRecord::StatementInvalid)
    expect(described_class.explains?(error)).to be(false)
  end

  [ PG::LockNotAvailable, PG::QueryCanceled, PG::UndefinedTable, PG::InvalidCatalogName ].each do |pg_error|
    it "does not explain a statement that failed with #{pg_error}" do
      expect(described_class.explains?(wrapped(pg_error))).to be(false)
    end
  end

  it "does not explain a database role or shard nobody configured" do
    expect(described_class.explains?(ActiveRecord::ConnectionNotDefined.new("no pool"))).to be(false)
  end

  it "does not explain a record that is not there" do
    expect(described_class.explains?(ActiveRecord::RecordNotFound.new("gone"))).to be(false)
  end

  it "does not explain a failure outside the database" do
    expect(described_class.explains?(ArgumentError.new("string contains null byte"))).to be(false)
  end
end
