# frozen_string_literal: true

require 'net/http'
require_relative '../../lib/debug/server'
require_relative '../../lib/debug/collector'

RSpec.describe Debug::Server do
  class StaticProbe
    def snapshot = { value: 42 }
  end

  let(:collector) { Debug::Collector.new(probes: { static: StaticProbe.new }, frame_interval: 1) }

  subject(:server) { described_class.new(collector:, port: 0) }

  before do
    server.start
    collector.sample!
  end

  after { server.stop }

  it 'sert la page de l UI' do
    response = Net::HTTP.get_response(URI("http://127.0.0.1:#{server.port}/"))

    expect(response.code).to eq('200')
    expect(response['content-type']).to eq('text/html')
    expect(response.body).to include('Gemboy')
  end

  it 'repond 404 sur un fichier inconnu' do
    response = Net::HTTP.get_response(URI("http://127.0.0.1:#{server.port}/nope.js"))

    expect(response.code).to eq('404')
  end

  it 'pousse le snapshot courant sur le flux SSE' do
    socket = TCPSocket.new('127.0.0.1', server.port)
    socket.write("GET /events HTTP/1.1\r\nHost: localhost\r\n\r\n")

    headers = +''
    headers << socket.readline until headers.include?("\r\n\r\n")
    expect(headers).to include('text/event-stream')

    payload = socket.readline
    expect(payload).to eq(%(data: {"static":{"value":42}}\n))
  ensure
    socket&.close
  end
end
