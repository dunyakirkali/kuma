require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe 'Kuma' do
  describe 'MD templates' do
    it 'should emit valid MD to STDOUT' do
      run_simple 'kuma'
      assert_exit_status(0)
    end
  end
end
