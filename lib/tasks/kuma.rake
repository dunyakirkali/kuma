namespace :kuma do
  desc "Smells"
  task :smell, :io do |t, args|
    Kuma.smell args[:io]
  end
end