require 'redis'
require 'active_support/notifications'

# Instrument Redis

class Redis::Client
  
  [:call, :call_pipeline, :call_loop].each do |method|
    define_method(:"#{method}_with_instrument") do |*args, &block|
      ActiveSupport::Notifications.instrument(Peek::Views::Redis.request_id) do
        send :"#{method}_without_instrument", *args, &block
      end
    end
  
    alias_method_chain method, :instrument
  end

end

module Peek
  module Views
    class Redis < View
      def self.request_id
        "redis-#{ Thread.current.object_id }"
      end

      def results
        { :duration => formatted_duration, :calls => events.size }
      end

      private

      DURATION_THRESHOLD = 1000

      def setup_subscribers
        before_request do
          self.subscribers = []
          self.events      = []

          subscribers << subscribe(request_id) do |*args|
            events << ActiveSupport::Notifications::Event.new(*args)
          end
        end

        after_request do
          subscribers.each do |subscriber|
            ActiveSupport::Notifications.unsubscribe(subscriber)
          end
        end
      end

      def after_request
        subscribe 'process_action.action_controller' do |name, start, finish, id, payload|
          yield name, start, finish, id, payload
        end
      end

      def subscribers
        Thread.current[_subscribers_key]
      end

      def subscribers=(subscribers)
        Thread.current[_subscribers_key] = []
      end

      def events
        Thread.current[_events_key]
      end

      def events=(events)
        Thread.current[_events_key] = events
      end

      def request_id
        self.class.request_id
      end

      def duration
        events.inject(0) {|result, e| result += e.duration }
      end

      def formatted_duration
        ms = duration
        if ms >= DURATION_THRESHOLD
          "%.2fms" % ms
        else
          "%.0fms" % ( ms * DURATION_THRESHOLD )
        end
      end

      def _subscribers_key
        "#{ key }-subscribers"
      end

      def _events_key
        "#{ key }-events"
      end
    end
  end
end