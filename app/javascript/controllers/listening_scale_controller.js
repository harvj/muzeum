import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { percent: Number }

  connect() {
    this.element.style.setProperty("--listening-scale", `${this.percentValue}%`)
  }
}
