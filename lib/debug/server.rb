# frozen_string_literal: true

require 'json'
require 'socket'
require_relative '../debug'

module Debug
  class Server
    UI_ROOT = File.expand_path('../../assets/debug_ui', __dir__)
    POLL_INTERVAL = 0.05
    CONTENT_TYPES = { '.html' => 'text/html', '.js' => 'application/javascript', '.css' => 'text/css' }.freeze
    SSE_HEADERS = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n" \
                  "Cache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"

    attr_reader :port

    def initialize(collector:, port: DEFAULT_PORT, logger: nil)
      @collector = collector
      @logger = logger
      @socket = TCPServer.new('127.0.0.1', port)
      @port = @socket.addr[1]
    end

    def start
      @logger&.info { "Debug UI on http://127.0.0.1:#{port}" }
      @thread = Thread.new { accept_loop }
    end

    def stop
      @thread&.kill
      @socket.close unless @socket.closed?
    end

    private

    def accept_loop
      loop do
        client = @socket.accept
        Thread.new { handle(client) }
      end
    rescue IOError, Errno::EBADF
      nil
    end

    def handle(client)
      path = client.readline.split[1]
      loop { break if client.readline == "\r\n" }
      path == '/events' ? stream_events(client) : serve_static(client, path)
    rescue EOFError, Errno::EPIPE, Errno::ECONNRESET
      nil
    ensure
      client.close unless client.closed?
    end

    def stream_events(client)
      client.write(SSE_HEADERS)
      last_sequence = -1
      loop do
        sequence = @collector.sequence
        if sequence != last_sequence
          last_sequence = sequence
          client.write("data: #{JSON.generate(@collector.latest)}\n\n")
        end
        sleep(POLL_INTERVAL)
      end
    end

    def serve_static(client, path)
      # File.basename is what keeps "/../../etc/passwd" inside UI_ROOT.
      name = path == '/' ? 'index.html' : File.basename(path)
      file = File.join(UI_ROOT, name)
      return respond(client, '404 Not Found', 'text/plain', 'not found') unless File.file?(file)

      respond(client, '200 OK', CONTENT_TYPES.fetch(File.extname(file), 'text/plain'), File.read(file))
    end

    def respond(client, status, content_type, body)
      client.write("HTTP/1.1 #{status}\r\nContent-Type: #{content_type}\r\n" \
                   "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
    end
  end
end
