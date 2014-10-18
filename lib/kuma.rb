# lib/kuma.rb
class Kuma
  def self.smell io
    flay io
    flog io
    rubocop io
  end
  
  private
  
  def self.flay io
    io.write('# flay')
    io.write(%x(flay app))
  end
  
  def self.flog io
    io.write('# flog')
    io.write(%x(flog app))
  end
  
  def self.rubocop io
    io.write('# rubocop')
    io.write(%x(rubocop app))
  end
  
  def self.root
    File.dirname __dir__
  end
end