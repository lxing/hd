#!/usr/bin/ruby

# This server is intended to replace the old scraping-based dashboard in analytics/monitoring

require "json"
require "rest-client"
require "sinatra/base"

class HasturDashboard < Sinatra::Base

  set :port, 8123

  # Hastur's REST API returns gauges in the form 
  # { 
  #   UUID => {
  #     metric.name => {
  #       timestamp1 => value1,
  #       timestamp2 => value2,
  #       ...
  #     }
  #   }
  # }
  # For multiple metrics queried with a wildcard like "metric*" or separated by
  # commas, there will be multiple entries in the UUID hash. 

  PREFIX = "player_log_metrics." # All mr metrics begin with this prefix
  PATH, TYPE = "http://hastur.ooyala.com/api/name/", "/value"
  UUID = "8ce94590-bd8d-012f-4d65-00163e0001a4" # Identifier for the machine that pushed the metrics

  FIVE_MINUTES = 5 * 60.0
  DEFAULT_RANGE = :two_days

  get "/player_dashboard" do
    player_loads, player_displays, module_failures = gauge_metrics([
      "#{PREFIX}log.player_load.count",
      "#{PREFIX}log.player_display.count",
      "#{PREFIX}warning.module_load_failed.count"
    ])

    module_failures_normalized = normalize(module_failures, player_loads, 100)

    erb :player_dashboard, :locals => {
      :loads_data => serialize(player_loads),
      :displays_data => serialize(player_displays),
      :module_failures_data => serialize(module_failures),
      :module_failures_normalized_data => serialize(module_failures_normalized, 1)
    }
  end

  get "/sas_dashboard" do
    couldnt_contact, couldnt_contact_new, different_isauthorized, other_errors,
    client_latency50, client_latency90, client_latency95,
    server_latency50, server_latency90, server_latency95,
    authorize_counts = gauge_metrics([
      "#{PREFIX}error.could_not_contact.count",
      "#{PREFIX}error.could_not_contact_new.count",
      "#{PREFIX}error.different_isAuthorized.count",
      "#{PREFIX}error.other.count",
      "#{PREFIX}log.sas_client_latency.tp50",
      "#{PREFIX}log.sas_client_latency.tp90",
      "#{PREFIX}log.sas_client_latency.tp95",
      "#{PREFIX}log.sas_server_latency.tp50",
      "#{PREFIX}log.sas_server_latency.tp90",
      "#{PREFIX}log.sas_server_latency.tp95",
      "#{PREFIX}log.sas_authorize_v2.count"
    ])

    couldnt_contact = combine(couldnt_contact, couldnt_contact_new)
    couldnt_contact_normalized = normalize(couldnt_contact, authorize_counts, 100)

    erb :sas_dashboard, :locals => {
      :couldnt_contact_data => serialize(couldnt_contact),
      :different_isauthorized_data => serialize(different_isauthorized, 0.5),
      :other_errors_data => serialize(other_errors, 0.5),
      :client_latency_data => serialize([client_latency50, client_latency90, client_latency95], 1),
      :server_latency_data => serialize([server_latency50, server_latency90, server_latency95], 1),
      :authorize_counts_data => serialize(authorize_counts),

      :couldnt_contact_normalized_data => serialize(couldnt_contact_normalized)
    }
  end

  # Query a single metric, remove the UUID and metric.name wrapper hashes
  def gauge_metric(metric, params = { :ago => DEFAULT_RANGE })
    gauge_metrics([metric], params)[0]
  end

  # Query multiple metrics, remove the UUID and metric.name wrapper hashes
  # It's desirable to doo all of them at once to avoid making multiple REST requests
  # to the Hastur server
  def gauge_metrics(metrics, params = { :ago => DEFAULT_RANGE })
    metrics_request_string = metrics.join(',')
    metrics_json = query_api(metrics_request_string, params)

    metrics.map { |metric_name| metrics_json[metric_name] }
  end

  # Query a wildcard metric, remove the UUID wrapper hash, and combine all matching metrics
  def gauge_wildcard(wildcard_metric, params = { :ago => DEFAULT_RANGE })
    gauges = gauges(wildcard_metric, params)
    gauges.values.reduce({}) { |acc, val| combine(val, acc) }
  end

  # Query a specific or wildcarded metric, remove the UUID wrapper hash
  def query_api(metrics_request_string, params)
    begin
      data = RestClient.get(PATH + metrics_request_string + TYPE, :params => params)
      JSON.parse(data)[UUID]
    rescue Exception => e
      puts e.backtrace
      {}
    end
  end

  # Functions to transform unwrapped gauges (pure timestamp => value hashes)

  def last(gauges)
    gauges.values.last
  end

  def sum(gauges)
    gauges.values.reduce(0) { |acc, val| acc + val.to_i }
  end

  def avg(gauges)
    sum(gauges) / gauges.size
  end

  # Sum the values of two gauges.
  def combine(a, b)
    ret = {}
    a.each_key do |k|
      ret[k] = a[k].to_i + b[k].to_i
    end
    ret
  end

  # Normalize the values of one gauge against another; eg. failures out of all pings.
  # Set scale = 100 to generate a percentage.
  def normalize(a, b, scale = 1)
    ret = {}
    a.keys.each do |k|
      next unless b[k]
      ret[k] = a[k].to_f / b[k].to_i * scale
    end
    ret
  end

  # Serializes the data for Rickshaw graphs. Rickshaw accepts data as an array of javascript
  # objects in the form {x: 100, y: 200}, where x is epoch seconds.
  #
  # Can pass in a single gauge or multiple gauges, in which case they'll be concatenated
  # into multiple lines on the final graph
  def serialize(gauges, bucket_size = FIVE_MINUTES)
    gauges = [gauges] unless gauges.is_a? Array

    # Update the timestamps to reflect seconds instead of Hastur's microseconds.
    # Normalize the counts by dividing by bucket size in seconds to capture pings per second.
    data = gauges.reduce([]) do |serialized, gauge|
      serialized << gauge.keys.sort.map do |timestamp|
        { "x" => timestamp.to_i / 1000000,
          "y" => gauge[timestamp].to_i / bucket_size }
      end
    end

    data.to_json.delete('\"')
  end

  run!

end
