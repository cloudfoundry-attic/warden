module Warden
  module Protocol

    class SpawnRequest
      def filtered_fields
        [:script]
      end
    end
  end
end
