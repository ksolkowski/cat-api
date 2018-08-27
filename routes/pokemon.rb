require "yaml"

class CatApi < Roda
  route('pokemon') do |r|
    pokemans = YAML.load_file("./config/pokemon/recipies.yml")
    sorty = YAML.load_file("./config/pokemon/sort_order.yml")
    available = pokemans.map{|x| x["Pokemon Attracted"] }.flatten.map{|x| x.split(" - ").first }.uniq.sort_by{|x| sorty[x].to_i }

    r.get ":name", String do |name|
      pokemans.select{|x| x["Pokemon Attracted"].any?{|z| z.parameterize.include?(name)} }
    end

    r.get "" do
      available.map{|x| "<a href=\"/pokemon/#{x.parameterize}\">#{x}</a>" }.join("<br>")
    end



  end
end