require 'spec_helper'

describe OpenStudioAmis do

  context "version 1" do
    it "should default to an ami if nothing passed" do
      a = OpenStudioAmis.new
      amis = a.get_amis

      expect(amis[:server]).not_to be_nil
      expect(amis[:worker]).not_to be_nil
      expect(amis[:cc2worker]).not_to be_nil
    end

    it "should return specific amis if passed a version" do
      a = OpenStudioAmis.new(1, {:openstudio_version => "1.2.0"})

      amis = a.get_amis

      expect(amis[:server]).to eq("ami-a3edddca") 
      expect(amis[:worker]).to eq("ami-bfedddd6") 
      expect(amis[:cc2worker]).to eq("ami-b5eddddc") 
    end
    
    it "should list all amis" do
      a = OpenStudioAmis.new(1).list
      
      expect(a).not_to be_nil
    end
  end
  
  context "version 2" do
    it "should default the server version" do
      
    end
  end
end