import { Controller } from "@hotwired/stimulus"
import { artworkTreatment } from "site_art_presentation"

const refreshInterval = 60000
const imageTimeout = 5000

export default class extends Controller {
  static values = { urls: Object }

  connect() {
    const body = this.element.parentElement
    this.regions = {
      top: body.querySelector(":scope > header"),
      default: body.querySelector(":scope > main"),
      bottom: body.querySelector(":scope > footer")
    }
    this.snapshot = this.urlsValue
    this.refreshTimer = setInterval(() => this.refreshSnapshot(), refreshInterval)
    this.scheme = matchMedia("(prefers-color-scheme: dark)")
    this.updateBackground = () => this.showBackground()
    this.scheme.addEventListener("change", this.updateBackground)
    this.appearance = new MutationObserver(this.updateBackground)
    this.appearance.observe(document.documentElement, {
      attributes: true, attributeFilter: ["data-appearance"]
    })
    this.clearIcon = () => {
      this.iconLoad?.abort()
      this.icon?.remove()
    }
    this.prepareCache = () => {
      this.backgroundLoad?.abort()
      this.clearBackground()
    }
    document.addEventListener("turbo:before-cache", this.prepareCache)
    document.addEventListener("turbo:before-render", this.clearIcon)
    this.showBackground()
    this.showIcon()
  }

  disconnect() {
    clearInterval(this.refreshTimer)
    this.snapshotLoad?.abort()
    this.snapshotLoad = undefined
    this.backgroundKey = undefined
    this.iconURL = undefined
    this.scheme.removeEventListener("change", this.updateBackground)
    this.appearance.disconnect()
    document.removeEventListener("turbo:before-cache", this.prepareCache)
    document.removeEventListener("turbo:before-render", this.clearIcon)
    this.clearIcon()
    this.backgroundLoad?.abort()
    this.clearBackground()
  }

  async refreshSnapshot() {
    if (document.hidden || this.snapshotLoad) return
    const load = this.snapshotLoad = new AbortController()
    const timeout = setTimeout(() => load.abort(), imageTimeout)
    try {
      const response = await fetch("/site-art", {
        credentials: "omit", redirect: "error", signal: load.signal
      })
      if (!response.ok) return
      const snapshot = await response.json()
      if (load.signal.aborted || !/^[a-f0-9]{64}$/.test(snapshot?.release ?? "")) return
      this.snapshot = snapshot
      this.showBackground()
      this.showIcon()
    } catch (_) {
      // Preserve the current image and treatment when refresh fails.
    } finally {
      clearTimeout(timeout)
      if (this.snapshotLoad === load) this.snapshotLoad = undefined
    }
  }

  clearBackground() {
    this.background?.remove()
    this.background = undefined
    this.applyTreatment()
  }

  applyTreatment(record) {
    for (const [region, element] of Object.entries(this.regions)) {
      const values = record ? artworkTreatment(record, region) : {}
      for (const name of ["foreground", "text-shadow", "backing"]) {
        const property = `--art-${name}`
        if (values[name]) element.style.setProperty(property, values[name])
        else element.style.removeProperty(property)
      }
      element.toggleAttribute("data-art-treatment", Object.values(values).some(Boolean))
    }
  }

  async showBackground() {
    const appearance = document.documentElement.dataset.appearance
    const theme = appearance === "light" || appearance === "dark"
      ? appearance : (this.scheme.matches ? "dark" : "light")
    const record = this.snapshot[theme]
    const key = JSON.stringify([theme, this.snapshot.release, record])
    if (key === this.backgroundKey) return

    this.backgroundKey = key
    this.backgroundLoad?.abort()
    if (this.background && this.background.getAttribute("src") === record?.url) {
      this.applyTreatment(record)
      return
    }

    if (!record) {
      this.clearBackground()
      return
    }

    const load = this.backgroundLoad = new AbortController()
    const image = await this.decode(record.url, load.signal)
    if (load.signal.aborted) return

    this.clearBackground()
    if (!image) return

    image.className = "site-art-background"
    image.alt = ""
    image.dataset.turboTemporary = ""
    image.addEventListener("error", () => {
      if (this.background === image) this.clearBackground()
    }, { once: true })
    this.background = image
    this.element.prepend(image)
    this.applyTreatment(record)
  }

  async showIcon() {
    const url = this.snapshot.favicon
    if (url === this.iconURL) return

    this.iconURL = url
    this.clearIcon()
    const load = this.iconLoad = new AbortController()
    const image = await this.decode(url, load.signal)
    if (!image || load.signal.aborted) return

    const icon = this.icon = document.createElement("link")
    icon.rel = "icon"
    icon.crossOrigin = "anonymous"
    icon.referrerPolicy = "no-referrer"
    if (url.endsWith(".svg")) icon.sizes = "any"
    icon.href = url
    icon.addEventListener("error", this.clearIcon, { once: true })
    document.head.append(icon)
  }

  async decode(url, signal) {
    if (!url) return

    const image = new Image()
    image.crossOrigin = "anonymous"
    image.referrerPolicy = "no-referrer"
    image.fetchPriority = "low"
    const cancel = () => image.removeAttribute("src")
    signal.addEventListener("abort", cancel, { once: true })
    const timeout = setTimeout(cancel, imageTimeout)
    try {
      image.src = url
      await image.decode()
      return image
    } catch (_) {
      // The selection key prevents retrying this candidate on an unchanged snapshot.
    } finally {
      clearTimeout(timeout)
      signal.removeEventListener("abort", cancel)
    }
  }
}
