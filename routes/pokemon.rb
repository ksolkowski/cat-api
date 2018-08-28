require "yaml"

class CatApi < Roda
  route('pokemon') do |r|
    pokemans = YAML.load_file("./config/pokemon/recipies.yml")
    sorty = YAML.load_file("./config/pokemon/sort_order.yml")
    available = pokemans.map{|x| x["Pokemon Attracted"] }.flatten.map{|x| x.split(" - ").first }.uniq.sort_by{|x| sorty[x].to_i }

    r.get ":name", String do |name|
      @recipies = pokemans.select{|x| x["Pokemon Attracted"].any?{|z| z.parameterize.include?(name)} }.map do |recipie|
        r = recipie.dup
        r["Percent"] = recipie["Pokemon Attracted"].find{|z| z.parameterize.include?(name) }.split("-").last
        r.delete("Pokemon Attracted")
        r
      end

      @header = @recipies.first.keys
      view("pokemon/recipie")
    end

    r.get do
      @pokemon = available
      view("pokemon/index")
    end

  end
end