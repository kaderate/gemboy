# frozen_string_literal: true

RSpec.describe APU::ScopeBuffer do
  subject(:buffer) { described_class.new(4) }

  it 'ne rend que les echantillons ecrits tant qu il n est pas plein' do
    buffer.write(0.1)
    buffer.write(0.2)

    expect(buffer.to_a).to eq([0.1, 0.2])
  end

  it 'rend les echantillons du plus ancien au plus recent' do
    [1, 2, 3, 4].each { buffer.write(_1) }

    expect(buffer.to_a).to eq([1, 2, 3, 4])
  end

  it 'ecrase les plus anciens une fois plein' do
    [1, 2, 3, 4, 5, 6].each { buffer.write(_1) }

    expect(buffer.to_a).to eq([3, 4, 5, 6])
  end
end
