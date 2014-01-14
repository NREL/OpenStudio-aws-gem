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
      a = OpenStudioAmis.new(1, "1.2.0", nil)

      amis = a.get_amis

      expect(amis['server']).to eq("ami-a3e4d4ca") 
      expect(amis['worker']).to eq("ami-b9e4d4d0") 
      expect(amis['cc2worker']).to eq("ami-a5e4d4cc") 
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

