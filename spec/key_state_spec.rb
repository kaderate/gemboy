require_relative '../lib/key_state'

RSpec.describe KeyState do
  describe "initialization" do
    it "initializes all keys as unpressed" do
      ks = KeyState.new
      hash = ks.to_h
      expect(hash[:up]).to eq(false)
      expect(hash[:down]).to eq(false)
      expect(hash[:left]).to eq(false)
      expect(hash[:right]).to eq(false)
      expect(hash[:a]).to eq(false)
      expect(hash[:b]).to eq(false)
      expect(hash[:start]).to eq(false)
      expect(hash[:select]).to eq(false)
    end
  end

  describe "#update" do
    let(:ks) { KeyState.new }

    it "sets up button when 'up' key is pressed" do
      ks.update('up', true)
      expect(ks.to_h[:up]).to eq(true)
    end

    it "clears up button when 'up' key is released" do
      ks.update('up', true)
      ks.update('up', false)
      expect(ks.to_h[:up]).to eq(false)
    end

    it "sets down button" do
      ks.update('down', true)
      expect(ks.to_h[:down]).to eq(true)
    end

    it "sets left button" do
      ks.update('left', true)
      expect(ks.to_h[:left]).to eq(true)
    end

    it "sets right button" do
      ks.update('right', true)
      expect(ks.to_h[:right]).to eq(true)
    end

    it "sets A button with 'a' key" do
      ks.update('a', true)
      expect(ks.to_h[:a]).to eq(true)
    end

    it "sets B button with 'b' key" do
      ks.update('b', true)
      expect(ks.to_h[:b]).to eq(true)
    end

    it "sets Start button with 'start' key" do
      ks.update('start', true)
      expect(ks.to_h[:start]).to eq(true)
    end

    it "sets Select button with 'select' key" do
      ks.update('select', true)
      expect(ks.to_h[:select]).to eq(true)
    end

    it "handles multiple buttons pressed simultaneously" do
      ks.update('up', true)
      ks.update('a', true)
      ks.update('start', true)
      hash = ks.to_h
      expect(hash[:up]).to eq(true)
      expect(hash[:a]).to eq(true)
      expect(hash[:start]).to eq(true)
      expect(hash[:down]).to eq(false)
    end

    it "clears one button without affecting others" do
      ks.update('up', true)
      ks.update('down', true)
      ks.update('up', false)
      hash = ks.to_h
      expect(hash[:up]).to eq(false)
      expect(hash[:down]).to eq(true)
    end
  end

  describe "#to_h" do
    it "returns a hash with all button states" do
      ks = KeyState.new
      ks.update('up', true)
      ks.update('a', true)
      hash = ks.to_h
      expect(hash).to be_a(Hash)
      expect(hash.keys).to include(:up, :down, :left, :right, :a, :b, :start, :select)
    end

    it "reflects current state of all buttons" do
      ks = KeyState.new
      ks.update('up', true)
      ks.update('down', true)
      ks.update('left', false)
      hash = ks.to_h
      expect(hash[:up]).to eq(true)
      expect(hash[:down]).to eq(true)
      expect(hash[:left]).to eq(false)
    end
  end

  describe "button mapping" do
    it "maps keyboard keys to Game Boy buttons correctly" do
      ks = KeyState.new

      # Directional buttons
      ks.update('up', true)
      ks.update('down', true)
      ks.update('left', true)
      ks.update('right', true)

      # Action buttons
      ks.update('a', true)
      ks.update('b', true)
      ks.update('start', true)
      ks.update('select', true)

      hash = ks.to_h
      expect(hash[:up]).to eq(true)
      expect(hash[:down]).to eq(true)
      expect(hash[:left]).to eq(true)
      expect(hash[:right]).to eq(true)
      expect(hash[:a]).to eq(true)
      expect(hash[:b]).to eq(true)
      expect(hash[:start]).to eq(true)
      expect(hash[:select]).to eq(true)
    end
  end
end
