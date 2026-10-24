# frozen_string_literal: true

module Statifier
  module Driver
    # The session id the driver mints when the host names none, as the
    # reference mints one (`Statifier.MachineState.generate_session_id/0`
    # in statifier-ex): `sess_`, then a 48-bit millisecond timestamp and 80
    # random bits written in lower-case Crockford base32, so ids sort by the
    # millisecond they were minted in.
    #
    # @api private
    module SessionId
      # Crockford base32's alphabet, in symbol order.
      ALPHABET = "0123456789abcdefghjkmnpqrstvwxyz"

      # The timestamp's width in bits.
      TIME_BITS = 48

      # The random part's width in bytes.
      RANDOM_BYTES = 10

      module_function

      # A fresh session id.
      #
      # @return [String]
      def mint
        millis = Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond) & ((1 << TIME_BITS) - 1)
        encode((millis << (RANDOM_BYTES * 8)) | Random.urandom(RANDOM_BYTES).unpack1("H*").to_i(16))
      end

      # The 128 bits of `value` in base32, the last symbol padded with two
      # zero bits, as an unpadded base32 encoding of 16 bytes writes them.
      def encode(value)
        padded = value << 2
        "sess_#{25.downto(0).map { |digit| ALPHABET[(padded >> (5 * digit)) & 31] }.join}"
      end
    end
  end
end
