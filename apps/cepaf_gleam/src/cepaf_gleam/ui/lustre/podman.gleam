/// Lustre component for Podman plane (SC-GLM-UI-001).
/// Manages container, image, volume, and network state from Podman API.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
///
/// MoZ wiring (SC-ZMOF-005): StartContainer/StopContainer mark the target
/// container status as "pending" in the model so the UI shows an in-flight
/// indicator while the Zenoh MoZ request is in transit to the Rust daemon.
/// The actual mutation fires via:
///   moz_client.send_request(moz_state, "restart", params)  -- StartContainer
///   moz_client.send_request(moz_state, "drain",   params)  -- StopContainer
/// Confirmation arrives as a ContainersLoaded msg from the SSE feed.
import cepaf_gleam/ui/domain.{Podman}
import cepaf_gleam/ui/zenoh_otel
import gleam/list

pub type PodmanModel {
  PodmanModel(
    containers: List(Container),
    images: List(Image),
    volumes: List(Volume),
    networks: List(Network),
  )
}

pub type Container {
  Container(id: String, name: String, status: String, image: String)
}

pub type Image {
  Image(id: String, repository: String, tag: String, size_mb: Int)
}

pub type Volume {
  Volume(name: String, driver: String, mountpoint: String)
}

pub type Network {
  Network(name: String, driver: String, subnet: String)
}

pub type PodmanMsg {
  ContainersLoaded(List(Container))
  ImagesLoaded(List(Image))
  StartContainer(String)
  StopContainer(String)
  RefreshPodman
}

pub fn init() -> PodmanModel {
  PodmanModel(containers: [], images: [], volumes: [], networks: [])
}

pub fn update(model: PodmanModel, msg: PodmanMsg) -> PodmanModel {
  zenoh_otel.emit(Podman, "update", zenoh_otel.Act)
  case msg {
    ContainersLoaded(cs) -> PodmanModel(..model, containers: cs)
    ImagesLoaded(imgs) -> PodmanModel(..model, images: imgs)
    // Mark the target container "pending" so the UI shows an in-flight
    // indicator while the MoZ "restart" request is dispatched over Zenoh.
    // When the containers list is empty the map is a no-op (model unchanged).
    StartContainer(id) ->
      PodmanModel(
        ..model,
        containers: list.map(model.containers, fn(c) {
          case c.id == id {
            True -> Container(..c, status: "pending")
            False -> c
          }
        }),
      )
    // Mark the target container "pending" while the MoZ "drain" request
    // is in transit.  The SSE feed delivers ContainersLoaded to confirm.
    StopContainer(id) ->
      PodmanModel(
        ..model,
        containers: list.map(model.containers, fn(c) {
          case c.id == id {
            True -> Container(..c, status: "pending")
            False -> c
          }
        }),
      )
    RefreshPodman -> model
  }
}

pub fn running_containers(model: PodmanModel) -> List(Container) {
  list.filter(model.containers, fn(c) { c.status == "running" })
}

pub fn container_count(model: PodmanModel) -> Int {
  list.length(model.containers)
}

pub fn running_count(model: PodmanModel) -> Int {
  list.length(running_containers(model))
}
