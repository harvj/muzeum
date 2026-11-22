import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { clock: Boolean, dateOnly: Boolean }

  connect() {
    const timestamp = new Date(this.element.dateTime)
    if (Number.isNaN(timestamp.getTime())) return

    const options = { dateStyle: "medium" }
    if (this.clockValue) {
      this.element.textContent = new Intl.DateTimeFormat(undefined, { hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(timestamp)
      return
    }
    if (!this.dateOnlyValue) options.timeStyle = "short"
    this.element.textContent = new Intl.DateTimeFormat(undefined, options).format(timestamp)
  }
}
