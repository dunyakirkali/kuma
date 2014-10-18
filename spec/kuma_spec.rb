require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Kuma" do
  before :all do
    %x(rails new app)
  end

  it ".smell should run flay" do
    testIO = StringIO.new
    Kuma.smell testIO
    testIO.string.should include('# flay')
  end

  it ".smell should run flog" do
    testIO = StringIO.new
    Kuma.smell testIO
    testIO.string.should include('# flog')
  end
  
  after :all do
    %x(rm -rf app)
  end
end
