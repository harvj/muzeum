module LibraryPresentationHelper
  def dense_table(label, classes: nil, &block)
    tag.div(class: "table-scroll") do
      tag.table(capture(&block), class: [ "catalog-table", classes ], aria: { label: })
    end
  end

  def entity_link(label, path)
    link_to label, path, class: "entity-link"
  end
end
