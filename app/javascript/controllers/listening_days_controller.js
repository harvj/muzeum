import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.clearHeadings()
    const day = new Intl.DateTimeFormat(undefined, { dateStyle: "full" })
    let previous
    for (const row of Array.from(this.element.rows)) {
      const time = row.querySelector("time")
      if (!time) continue

      const label = day.format(new Date(time.dateTime))
      if (label === previous) continue

      const heading = document.createElement("tr")
      heading.className = "listening-day"
      const cell = document.createElement("th")
      cell.scope = "row"
      cell.colSpan = row.cells.length
      cell.textContent = label
      heading.append(cell)
      row.before(heading)
      previous = label
    }
  }

  clearHeadings() {
    this.element.querySelectorAll(".listening-day").forEach(row => row.remove())
  }
}
