namespace :kuma do
  desc "Smells"
  task smell: :environment do
    Kuma.smell args[:io]
  end
end