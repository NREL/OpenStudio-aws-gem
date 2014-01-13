require 'spec_helper'

describe OpenStudioAmis do

  context "version 1" do
    it "should default to an ami if nothing passed" do
      a = OpenStudioAmis.new
      amis = a.get_amis

      expect(amis['server']).not_to be_nil
      expect(amis['worker']).not_to be_nil
      expect(amis['cc2worker']).not_to be_nil
    end

    it "should return specific amis if passed a version" do
      a = OpenStudioAmis.new(1, "1.2.0")

      amis = a.get_amis

      expect(amis['server']).to eq("ami-29e5cd40") 
      expect(amis['worker']).to eq("ami-a9e4ccc0") 
      expect(amis['cc2worker']).to eq("ami-5be4cc32") 
    end

  end

end

