import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const timestamp = new Date(this.element.dateTime)
    if (Number.isNaN(timestamp.getTime())) return

    this.element.textContent = new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "short"
    }).format(timestamp)
  }
}
