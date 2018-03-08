Sequel.migration do
  change do
    add_column :images, :width, :integer
    add_column :images, :height, :integer

    add_index  :images, :hashed_key
  end
end