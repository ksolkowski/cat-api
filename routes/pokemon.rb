require "yaml"

class CatApi < Roda
  route('pokemon') do |r|
    pokemans = YAML.load_file("./config/pokemon/recipies.yml")
    sorty = YAML.load_file("./config/pokemon/sort_order.yml")
    available = pokemans.map{|x| x["Pokemon"] }.flatten.map{|x| x.split(" - ").first }.
                inject(Hash.new(0)){|h, p| h[p]+=1;h }.sort_by{|p, c| sorty[p].to_i }

    all_recipies = YAML.load_file("./config/pokemon/recipies.yml")
    @header = all_recipies.map{|x| x["Name"] }.uniq.map do |recipie|
      { name: recipie.humanize, url: "/pokemon/recipies/#{recipie.parameterize}" }
    end

    def find_recipies(name, pokemans)
      pokemans.select{|x| x["Pokemon"].any?{|z| z.include?(name)} }.map do |recipie|
        r = recipie.dup
        r["Percent"] = recipie["Pokemon"].find{|z| z.include?(name) }.split("-").last.strip
        r.delete("Pokemon")
        r
      end.sort_by do |r|
        rarity = r["Rarity"]
        if rarity == "Basic"
          0
        elsif rarity == "Good" or rarity.start_with?("Good")
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

    r.on "recipies" do
      r.on(:name) do
        @recipies = all_recipies.select{|x| x["Name"].parameterize == r.params["name"] }
        view("pokemon/recipie")
      end

      r.is do
        r.get do
          @recipies = all_recipies.map do |recipie|
            name = recipie["Name"]
            {
              "name" => name,
              "attracts" => recipie["Attracts"],
              "url" => "/pokemon/recipies/#{name.parameterize}"
            }
          end.uniq
          view("pokemon/recipies")
        end
      end
    end

    r.get do
      @pokemon = available.map do |name, count|
        details = find_recipies(name, pokemans)
        max_percent = details.max_by{|x| x["Percent"].gsub("%", "").to_f }
        {"name" => name, "count" => count, "details" => details, "max_percent" => max_percent}
      end

      view("pokemon/index")
    end

  end
end