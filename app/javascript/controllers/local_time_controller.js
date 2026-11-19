import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { clock: Boolean }

  connect() {
    const timestamp = new Date(this.element.dateTime)
    if (Number.isNaN(timestamp.getTime())) return

    this.element.textContent = new Intl.DateTimeFormat(undefined, this.clockValue ?
      { timeStyle: "short" } : { dateStyle: "medium", timeStyle: "short" }).format(timestamp)
  }
}
