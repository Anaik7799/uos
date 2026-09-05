type fpp_port = { name: string; typ: string }
type fpp_component = { name: string; inputs: fpp_port list; outputs: fpp_port list }

let ffmpeg_decoder_comp = {
  name = "FFmpeg_Decoder";
  inputs = [ {name = "stream_in"; typ = "Video/MPEGTS"} ];
  outputs = [ {name = "raw_out"; typ = "Video/YUV"} ];
}

let ffmpeg_encoder_comp = {
  name = "FFmpeg_Encoder_H264";
  inputs = [ {name = "raw_in"; typ = "Video/YUV"} ];
  outputs = [ {name = "stream_out"; typ = "Video/H264"} ];
}
