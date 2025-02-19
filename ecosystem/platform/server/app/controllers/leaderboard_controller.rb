# frozen_string_literal: true

# Copyright (c) Aptos
# SPDX-License-Identifier: Apache-2.0

class LeaderboardController < ApplicationController
  IT1_METRIC_KEYS = %i[rank validator liveness participation latest_reported_timestamp].freeze
  IT1_RESULTS = File.read(File.join(Rails.root, 'public/it1_leaderboard_final.json'))
  It1Metric = Struct.new(*IT1_METRIC_KEYS)

  IT2_METRIC_KEYS = %i[rank validator liveness participation num_votes latest_reported_timestamp].freeze
  It2Metric = Struct.new(*IT2_METRIC_KEYS)

  IT3_METRIC_KEYS = %i[rank owner_address liveness rewards_growth last_epoch last_epoch_performance
                       governance_voting_record].freeze
  It3Metric = Struct.new(*IT3_METRIC_KEYS)

  def it1
    default_sort = [[:participation, -1], [:liveness, -1], [:latest_reported_timestamp, -1]]
    @metrics, @last_updated = Rails.cache.fetch(:it1_leaderboard, expires_in: 1.minute) do
      metrics = JSON.parse(IT1_RESULTS).map do |metric|
        timestamp = if metric['latest_reported_timestamp'].blank?
                      nil
                    else
                      DateTime.parse(metric['latest_reported_timestamp']).to_f
                    end
        It1Metric.new(
          -1,
          metric['validator'],
          metric['liveness'].to_f,
          metric['participation'].to_f,
          timestamp
        )
      end
      sort_metrics!(metrics, default_sort)
      metrics.each_with_index do |metric, i|
        metric.rank = i + 1
      end
      [metrics, Time.now]
    end

    @sort_columns = %w[rank liveness participation latest_reported_timestamp]
    sort = sort_params(@sort_columns)
    sort_metrics!(@metrics, sort) if sort
  end

  def it2
    default_sort = [[:num_votes, -1], [:participation, -1], [:liveness, -1], [:latest_reported_timestamp, -1]]
    @metrics, @last_updated = Rails.cache.fetch(:it2_leaderboard, expires_in: 1.minute) do
      response = HTTParty.get(ENV.fetch('LEADERBOARD_IT2_URL'))
      metrics = JSON.parse(response.body).map do |metric|
        timestamp = if metric['latest_reported_timestamp'].blank? ||
                       metric['latest_reported_timestamp'] == '1970-01-01 00:00:00+00:00'
                      nil
                    else
                      DateTime.parse(metric['latest_reported_timestamp']).to_f
                    end

        It2Metric.new(
          -1,
          metric['validator'],
          metric['liveness'].to_f,
          metric['participation'].to_f,
          metric['num_votes'].to_i,
          timestamp
        )
      end
      sort_metrics!(metrics, default_sort)
      metrics.each_with_index do |metric, i|
        metric.rank = i + 1
      end
      [metrics, Time.now]
    end

    @sort_columns = %w[rank liveness participation num_votes latest_reported_timestamp]
    sort = sort_params(@sort_columns)
    sort_metrics!(@metrics, sort) if sort.present?
  end

  def it3
    default_sort = [[:rewards_growth, -1], [:liveness, -1], [:last_epoch_performance, -1]]
    @metrics, @last_updated = Rails.cache.fetch(:it3_leaderboard, expires_in: 1.minute) do
      response = HTTParty.get(ENV.fetch('LEADERBOARD_IT3_URL'))
      metrics = JSON.parse(response.body).map do |metric|
        It3Metric.new(
          -1,
          metric['owner_address'],
          metric['liveness'].to_f,
          metric['rewards_growth'].to_f,
          metric['last_epoch'].to_i,
          metric['last_epoch_performance'],
          metric['governance_voting_record']
        )
      end
      sort_metrics!(metrics, default_sort)
      metrics.each_with_index do |metric, i|
        metric.rank = i + 1
      end
      [metrics, Time.now]
    end

    @sort_columns = %w[rank liveness rewards_growth last_epoch last_epoch_performance governance_voting_record]
    sort = sort_params(@sort_columns)
    sort_metrics!(@metrics, sort) if sort.present?
  end

  private

  def sort_params(valid_columns)
    helpers.parse_sort(params).filter_map do |key, direction|
      [key.to_sym, direction] if valid_columns.include? key
    end
  end

  def sort_metrics!(metrics, sort)
    metrics.sort_by! do |metric|
      sort.map do |key, direction|
        value = metric[key] || -Float::INFINITY
        if value.is_a?(String) && value.include?('/')
          numerator, denominator = value.split('/').map(&:strip)
          value = Rational(numerator, denominator)
          # When n=d, fractions with larger denominators should go first.
          value *= denominator.to_i if value == 1
        end
        value * direction
      end
    end
  end
end
