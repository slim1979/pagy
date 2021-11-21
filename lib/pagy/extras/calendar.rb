# See the Pagy documentation: https://ddnexus.github.io/pagy/extras/calendar
# frozen_string_literal: true

require 'pagy/calendar'

class Pagy # :nodoc:
  # Paginate based on calendar periods (year month week day) plus the regular pagination
  module CalendarExtra
    # Additions for the Backend module
    module Backend
      CONF_KEYS = %i[year month week day pagy active].freeze

      private

      # Take a collection and a conf Hash with keys in [:year, :month: week, :day, :pagy: :active];
      # The calendar is active by default, but it can be explicitly inactivated with `active: false`
      # Return a hash with 3 items:
      # 0. Array of pagy calendar unit objects
      # 1. Pagy object
      # 2. Array of results
      def pagy_calendar(collection, conf)
        unless conf.is_a?(Hash) && (conf.keys - CONF_KEYS).empty? && conf.all? { |k, v| v.is_a?(Hash) || k == :active }
          raise ArgumentError, "keys must be in #{CONF_KEYS.inspect} and object values must be Hashes; got #{conf.inspect}"
        end

        conf[:pagy]          = {} unless conf[:pagy]  # use default Pagy object when omitted
        calendar, collection = pagy_setup_calendar(collection, conf) unless conf.key?(:active) && !conf[:active]
        pagy, result         = send(conf[:pagy][:backend] || :pagy, collection, conf[:pagy])  # use backend: :pagy when omitted
        [calendar, pagy, result]
      end

      # Setup and return the calendar objects and the filtered collection
      def pagy_setup_calendar(collection, conf)
        units      = Calendar::UNITS.keys & conf.keys
        page_param = conf[:pagy][:page_param] || DEFAULT[:page_param]
        units.each do |unit|  # set all the :page_param vars for later deletion
          unit_page_param = :"#{unit}_#{page_param}"
          conf[unit][:page_param] = unit_page_param
          conf[unit][:page]       = params[unit_page_param]
        end
        calendar   = {}
        period     = pagy_calendar_period(collection)
        has_counts = respond_to?(:pagy_calendar_counts)
        units.each_with_index do |unit, index|
          params_to_delete      = units[(index + 1), units.size].map { |sub| conf[sub][:page_param] } + [page_param]
          conf[unit][:params]   = lambda do |params|  # delete page_param from the sub-units
                                    params_to_delete.each { |p| params.delete(p.to_s) } # Hash#except missing from 2.5 baseline
                                    params
                                  end
          conf[unit][:period]   = period
          calendar[unit]        = Calendar.create(unit, conf[unit])
          calendar[unit].counts = pagy_calendar_counts(collection, calendar[unit].filter_series) if has_counts
          period = calendar[unit].active_period # set the period for the next unit
        end
        [calendar, pagy_calendar_filter(collection, calendar[units.last].from, calendar[units.last].to)]
      end

      # This method must be implemented by the application.
      # It must return the the starting and ending local Time objects defining the calendar :period
      def pagy_calendar_period(*)
        # return_period_array_using(collection)
        raise NoMethodError, 'the pagy_calendar_period method must be implemented by the application and must return ' \
                             'the starting and ending local Time objects array defining the calendar :period'
      end

      # This method must be implemented by the application.
      # It receives the main collection and must return a filtered version of it.
      # The filter logic must be equivalent to {storage_time >= from && storage_time < to}
      def pagy_calendar_filter(*)
        # return_filtered_collection_using(collection, from, to)
        raise NoMethodError, 'the pagy_calendar_filter method must be implemented by the application and must return the ' \
                             'collection filtered by a logic equivalent to '\
                             '{storage_time >= from && storage_time < to}'
      end

      # This method may be implemented by the application.
      # filter_series example:
      # {1=>[2013-01-01 00:00:00 +0700, 2014-01-01 00:00:00 +0700],
      #  2=>[2014-01-01 00:00:00 +0700, 2015-01-01 00:00:00 +0700],
      #  3=>[2015-01-01 00:00:00 +0700, 2016-01-01 00:00:00 +0700],...}
      # If implemented it should return the count for each filter supplied by the filter_series. e.g:
      # {1=>23, 2=>0, 3=>15, ...}  (which will be available to the helpers as counts)
      # pagy_calendar_counts(collection, filter_series)
    end
  end
  Backend.prepend CalendarExtra::Backend
end
