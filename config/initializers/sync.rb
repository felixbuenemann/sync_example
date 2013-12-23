Sync.load_config(File.expand_path("../../sync.yml", __FILE__), Rails.env)

module Sync
  class FayeClientAuthTokenExtension
    def outgoing(message, callback)
      # Add auth_token to published internal messages
      message['ext'] ||= {}
      message['ext']['auth_token'] = Sync.auth_token

      callback.call(message)
    end
  end
  class RackAdapter < ::Faye::RackAdapter
    def initialize(app=nil, options=nil)
      super
      $faye_client = self.get_client
      $faye_client.add_extension(FayeClientAuthTokenExtension.new)
    end
  end
  module Clients
    class Faye
      class Message
        def self.batch_publish(messages)
          Rails.logger.info "Publishing #{messages.count} messages to /batch_publish"
          Sync.reactor.perform do
            $faye_client.publish('/batch_publish', messages.collect(&:to_hash).as_json)
          end
        end

        def publish
          Rails.logger.info "Publishing 1 message to #{channel}"
          Sync.reactor.perform do
            $faye_client.publish(channel, data.as_json)
          end
        end
      end
    end
  end
end

if Sync.adapter == "Faye"
  Faye::WebSocket.load_adapter('thin') if defined?(Thin)
  Faye::WebSocket.load_adapter('puma') if defined?(Puma)

  Rails.configuration.middleware.delete Rack::Lock
  #Rails.configuration.middleware.delete Rack::Lint
  Rails.configuration.middleware.insert_before Rails::Rack::Logger, Sync::RackAdapter,
      mount: Sync.config[:mount] || '/faye',
      timeout: Sync.config[:timeout] || 25,
      #engine: {type: Faye::Redis, host: 'localhost'},
      extensions: [Sync::FayeExtension.new]
end
