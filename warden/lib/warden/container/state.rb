module Warden
  module Container
    module State
      def self.from_s(state)
        const_get(state.capitalize)
      end

      class Base
        def self.to_s
          self.name.split("::").last.downcase
        end
      end

      # Container object created, but setup not performed
      class Born < Base;
      end

      # Container setup completed
      class Active < Base;
      end

      # Triggered by an error condition in the container (e.g. OOM) or
      # explicitly by the user. All processes have been killed but the
      # container exists for introspection. No new commands may be run.
      class Stopped < Base;
      end

      # All state associated with the container has been destroyed.
      class Destroyed < Base;
      end
    end
  end
end
