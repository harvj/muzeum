import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.querySelectorAll(".listening-day").forEach(row => row.remove())
    const day = new Intl.DateTimeFormat(undefined, { dateStyle: "full" })
    let previous, count, summary
    for (const row of Array.from(this.element.rows)) {
      const time = row.querySelector("time")
      if (!time) continue

      const label = day.format(new Date(time.dateTime))
      if (label !== previous) {
        const heading = document.createElement("tr")
        heading.className = "listening-day"
        heading.setAttribute("role", "row")
        const cell = document.createElement("th")
        cell.scope = "row"
        cell.setAttribute("role", "rowheader")
        cell.colSpan = row.cells.length
        cell.textContent = label
        summary = document.createElement("span")
        summary.className = "day-count"
        cell.append(summary)
        heading.append(cell)
        row.before(heading)
        count = 0
        previous = label
      }
      count += 1
      summary.textContent = `${count} shown`
    }
  }
}
