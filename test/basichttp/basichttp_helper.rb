# frozen_string_literal: true

require "statifier/basichttp"
require "stringio"

# The local test double the default transport is driven against: a
# connection that opens no socket. It takes the request Net::HTTP built and
# writes it, through Net::HTTP's own serializer, into a string, and it
# answers a response Net::HTTP's own parser reads from canned bytes.
module BasicHTTPHelper
  B = Statifier::BasicHTTP

  # The members of the request the tests make, unless one names another.
  REQUEST = { http_method: "POST", url: "http://localhost:8080/s1" }.freeze

  # A connection in place of a Net::HTTP object, holding what it was asked.
  class Connection
    attr_reader :started, :wire, :net_request

    # raw is the response's bytes; error, when given, is raised by request.
    def initialize(raw = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n", error: nil)
      @raw = raw
      @error = error
      @started = 0
    end

    def start
      @started += 1
      yield self
    end

    def request(net_request)
      raise @error if @error

      @net_request = net_request
      out = StringIO.new
      net_request.exec(Net::BufferedIO.new(out), "1.1", net_request.path)
      @wire = out.string
      parse(@raw)
    end

    private

    def parse(raw)
      socket = Net::BufferedIO.new(StringIO.new(raw))
      response = Net::HTTPResponse.read_new(socket)
      response.reading_body(socket, @net_request.response_body_permitted?) { nil }
      response
    end
  end

  # A transport over connection, recording every URI it was asked to
  # connect to in uris.
  def transport_over(connection, uris = [])
    B::NetHTTPTransport.new(connect: lambda { |uri|
      uris << uri
      connection
    })
  end

  def request(**members)
    B::Request.new(**REQUEST, **members)
  end
end
