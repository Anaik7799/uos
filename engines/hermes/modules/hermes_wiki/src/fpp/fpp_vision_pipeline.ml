open Fpp_model

let sensor_comp = 
  Component {
    name = "NUC-1_Camera_Sensor";
    kind = Active;
    ports = [ Port {name = "rtsp_out"; dir = Out; typ = "Video/H264"} ];
    state_machine = None;
  }

let inference_comp = 
  Component {
    name = "VM-1_PyTorch_Inference";
    kind = Active;
    ports = [ 
      Port {name = "rtsp_in"; dir = In; typ = "Video/H264"};
      Port {name = "bbox_out"; dir = Out; typ = "Data/JSON"} 
    ];
    state_machine = None;
  }

let transmuxer_comp = 
  Component {
    name = "Datarhei_Restreamer";
    kind = Passive;
    ports = [ 
      Port {name = "rtsp_in"; dir = In; typ = "Video/H264"};
      Port {name = "webrtc_out"; dir = Out; typ = "Video/WebRTC"} 
    ];
    state_machine = None;
  }

let zenoh_comp = 
  Component {
    name = "Zenoh_Mesh_Router";
    kind = Active;
    ports = [ 
      Port {name = "kpi_in"; dir = In; typ = "Data/JSON"};
      Port {name = "kpi_out"; dir = Out; typ = "Data/JSON"} 
    ];
    state_machine = None;
  }

let web_ui_comp = 
  Component {
    name = "Dream_Lwt_Dashboard";
    kind = Passive;
    ports = [ 
      Port {name = "webrtc_in"; dir = In; typ = "Video/WebRTC"};
      Port {name = "ws_in"; dir = In; typ = "Data/JSON"} 
    ];
    state_machine = None;
  }

let pipeline_topology = 
  Topology {
    name = "End_To_End_Vision_Pipeline";
    instances = [
      ("sensor", sensor_comp);
      ("inference", inference_comp);
      ("transmux", transmuxer_comp);
      ("zenoh", zenoh_comp);
      ("dashboard", web_ui_comp);
    ];
    connections = [
      Connection ("sensor", "rtsp_out", "inference", "rtsp_in");
      Connection ("inference", "bbox_out", "zenoh", "kpi_in");
      Connection ("sensor", "rtsp_out", "transmux", "rtsp_in");
      Connection ("transmux", "webrtc_out", "dashboard", "webrtc_in");
      Connection ("zenoh", "kpi_out", "dashboard", "ws_in");
    ];
  }
