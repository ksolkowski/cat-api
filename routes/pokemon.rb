require "yaml"

class CatApi < Roda
  route('pokemon') do |r|
    pokemans = YAML.load_file("./config/pokemon/recipies.yml")
    sorty = YAML.load_file("./config/pokemon/sort_order.yml")
    available = pokemans.map{|x| x["Pokemon Attracted"] }.flatten.map{|x| x.split(" - ").first }.
                inject(Hash.new(0)){|h, p| h[p]+=1;h }.sort_by{|p, c| sorty[p].to_i }

    def find_recipies(name, pokemans)
      pokemans.select{|x| x["Pokemon Attracted"].any?{|z| z.include?(name)} }.map do |recipie|
        r = recipie.dup
        r["Percent"] = recipie["Pokemon Attracted"].find{|z| z.include?(name) }.split("-").last
        r.delete("Pokemon Attracted")
        r
      end.sort_by do |r|
        rarity = r["Rarity"]
        if rarity == "Basic"
          0
        elsif rarity == "Good"
          1
        elsif rarity == "Very Good"
          2
        elsif rarity == "Special"
          3
        else
          4
        end
      end
    end

    r.get do
      @pokemon = available.map do |name, count|
        {"name" => name, "count" => count, "details" => find_recipies(name, pokemans)}
      end

      view("pokemon/index")
    end

  end
end