
type codec = H264 | H265 | VP8 | VP9 | AAC | Opus
type container = MP4 | MPEGTS | WebRTC | RTMP | RTSP
type hw_accel = None | VAAPI | NVENC | QuickSync

type filter_graph = 
  | Scale of int * int
  | Fps of int
  | Null

type ffmpeg_node = {
  id: string;
  source: string;
  hw_accel: hw_accel;
  video_codec: codec option;
  filters: filter_graph list;
  output_format: container;
  sink: string;
}
