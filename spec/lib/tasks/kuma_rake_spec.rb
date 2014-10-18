# spec/lib/tasks/kuma_rake_spec.rb
describe "kuma:smell" do
  include_context "rake"

  its(:prerequisites) { should include("environment") }

  xit "generates flay report" do
    io = StringIO.new
    subject.invoke
    io.string.should include('# flay')
  end
  
  xit "generates flog report" do
    io = StringIO.new
    subject.invoke io
    io.string.should include('# flog')
  end
end