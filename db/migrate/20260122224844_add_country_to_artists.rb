class AddCountryToArtists < ActiveRecord::Migration[8.1]
  def change
    add_column :artists, :country, :string
  end
end
