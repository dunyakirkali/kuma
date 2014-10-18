require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "Kuma" do
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
  
  it ".smell should run rubocop" do
    testIO = StringIO.new
    Kuma.smell testIO
    testIO.string.should include('# rubocop')
  end
end
