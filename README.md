# Detect AprilTags from a RealSense ROS 2 Bag

This guide reproduces AprilTag detection from an existing ROS 2 bag recorded
with an Intel RealSense camera. The physical camera does not need to be
connected during playback.

The example environment uses:

- Ubuntu 24.04
- ROS 2 Jazzy
- `apriltag_ros`
- A `tag36h11` marker whose outer black square is 50 mm × 50 mm
- Bag directory: `/home/fanchen/Desktop/rosbag2_2026_09_23-19_14_03`

## What the bag contains

Inspect the bag before starting:

```bash
source /opt/ros/jazzy/setup.bash
ros2 bag info /home/fanchen/Desktop/rosbag2_2026_09_23-19_14_03
```

The relevant recorded RealSense topics are:

```text
/camera/camera/color/image_raw
  sensor_msgs/msg/Image

/camera/camera/color/camera_info
  sensor_msgs/msg/CameraInfo

/camera/camera/aligned_depth_to_color/image_raw
  sensor_msgs/msg/Image

/camera/camera/depth/color/points
  sensor_msgs/msg/PointCloud2

/tf
  tf2_msgs/msg/TFMessage

/tf_static
  tf2_msgs/msg/TFMessage
```

The bag also contains Insta360 topics, but this procedure deliberately uses the
RealSense color image and its matching factory-calibrated CameraInfo.

The bag does not contain a recorded AprilTag detection topic. Detection is
therefore run again while the bag is playing.

## Install the required packages

```bash
sudo apt update
sudo apt install \
  ros-jazzy-apriltag-ros \
  ros-jazzy-rviz2 \
  ros-jazzy-tf2-tools
```

Every new terminal must source ROS:

```bash
source /opt/ros/jazzy/setup.bash
```

## Before starting

Stop any live RealSense driver or old AprilTag detector with `Ctrl+C`. Running
the live driver at the same time would create duplicate topic publishers.

The complete workflow uses separate terminals:

```text
Terminal 1: rosbag playback
Terminal 2: AprilTag detector
Terminal 3: detection messages
Terminal 4: TF/distance inspection
Terminal 5: RViz
```

## One-click launcher

The repository includes a launcher that starts bag playback, AprilTag
detection, detection output, and RViz:

```bash
chmod +x scripts/start_realsense_bag_apriltag.sh
./scripts/start_realsense_bag_apriltag.sh --check
./scripts/start_realsense_bag_apriltag.sh
```

It opens separate terminal windows for bag playback, the detector, and
detection messages, then starts RViz with
`config/realsense_bag_apriltag.rviz`. Close those terminal windows and RViz
to stop the workflow.

To use a different bag:

```bash
./scripts/start_realsense_bag_apriltag.sh /absolute/path/to/bag_directory
```

On this laptop, `Start RealSense AprilTag Bag.desktop` can also be copied to
the desktop and double-clicked.

## Terminal 1: replay the bag continuously

```bash
source /opt/ros/jazzy/setup.bash

ros2 bag play /home/fanchen/Desktop/rosbag2_2026_09_23-19_14_03 \
  --clock \
  --loop
```

- `--clock` publishes the recorded simulation clock.
- `--loop` starts again when the approximately 114-second recording ends.

Leave this terminal running. Do not start `realsense2_camera`; the bag is now
the camera-data publisher.

Verify playback in another terminal:

```bash
source /opt/ros/jazzy/setup.bash
ros2 topic hz /camera/camera/color/image_raw
```

Stop only the rate measurement with `Ctrl+C`. The recorded color stream is
approximately 14–15 Hz.

## Terminal 2: detect AprilTags in the recorded RealSense images

```bash
source /opt/ros/jazzy/setup.bash

ros2 run apriltag_ros apriltag_node --ros-args \
  -r __ns:=/apriltag_rs \
  -r image_rect:=/camera/camera/color/image_raw \
  -r camera_info:=/camera/camera/color/camera_info \
  -p family:=36h11 \
  -p size:=0.05 \
  -p pose_estimation_method:=pnp \
  -p qos_profile:=sensor_data \
  -p detector.threads:=4 \
  -p detector.decimate:=1.0 \
  -p use_sim_time:=true
```

Leave this terminal running.

Important settings:

- `image_rect` selects the recorded RealSense RGB image.
- `camera_info` selects the matching RealSense calibration.
- `size:=0.05` means a 50 mm outer black square.
- `pose_estimation_method:=pnp` enables 3D pose and TF.
- `use_sim_time:=true` makes the detector follow the bag clock.
- No tag-ID filter is configured, so IDs 0, 1, and 2 can all be detected.

For a 60 mm tag, use `size:=0.06`. An incorrect size produces incorrectly
scaled TF translation and distance.

## Terminal 3: read detection messages

```bash
source /opt/ros/jazzy/setup.bash
ros2 topic echo /apriltag_rs/detections
```

A successful result resembles:

```yaml
header:
  frame_id: camera_color_optical_frame
detections:
- family: tag36h11
  id: 2
  hamming: 0
  decision_margin: 111.38
  centre:
    x: 1051.90
    y: 793.04
```

The detector publishes every visible ID. A single message can contain IDs 0,
1, and 2 when all three are visible in the same recorded frame.

Interpretation:

- `detections: []`: synchronized input was processed, but no tag was decoded.
- No messages at all: check that Terminals 1 and 2 are still running.
- `hamming: 0`: no tag bits required correction.
- Higher `decision_margin`: generally a clearer detection.

## Terminal 4: inspect tag TF and distance

Check each visible tag separately:

```bash
source /opt/ros/jazzy/setup.bash

ros2 run tf2_ros tf2_echo \
  camera_color_optical_frame 'tag36h11:0' \
  --ros-args -p use_sim_time:=true
```

```bash
ros2 run tf2_ros tf2_echo \
  camera_color_optical_frame 'tag36h11:1' \
  --ros-args -p use_sim_time:=true
```

```bash
ros2 run tf2_ros tf2_echo \
  camera_color_optical_frame 'tag36h11:2' \
  --ros-args -p use_sim_time:=true
```

`tf2_echo` accepts one target tag at a time. RViz can display all available
tag frames simultaneously.

Example:

```text
Translation: [0.019, -0.024, 0.239]
```

In the RealSense optical frame:

- X: horizontal offset
- Y: vertical offset
- Z: forward distance

The straight-line camera-to-tag-center distance is:

```text
distance = sqrt(x² + y² + z²)
```

For the example:

```text
sqrt(0.019² + (-0.024)² + 0.239²) ≈ 0.241 m
```

## Terminal 5: visualize the replay in RViz

Start RViz using the bag clock:

```bash
source /opt/ros/jazzy/setup.bash
rviz2 --ros-args -p use_sim_time:=true
```

### Global Options

| Property | Value |
|---|---|
| Fixed Frame | `camera_link` |

### RealSense color image

Click **Add → By display type → Image**, then configure:

| Property | Value |
|---|---|
| Topic | `/camera/camera/color/image_raw` |
| Reliability | `Best Effort` |
| Durability | `Volatile` |
| History | `Keep Last` |
| Depth | `5` |

### RealSense point cloud

Click **Add → By display type → PointCloud2**, then configure:

| Property | Value |
|---|---|
| Topic | `/camera/camera/depth/color/points` |
| Reliability | `Best Effort` |
| Durability | `Volatile` |
| Style | `Points` |
| Size (Pixels) | `2` or `3` |
| Color Transformer | `RGB8` |
| Decay Time | `0` |

If RGB coloring is unavailable, try `AxisColor`.

### Camera and tag transforms

Click **Add → By display type → TF**. Expand its frame tree to see recorded
camera frames and any currently detected tag frames:

```text
camera_color_optical_frame
  ├── tag36h11:0
  ├── tag36h11:1
  └── tag36h11:2
```

A tag TF exists only while that tag is successfully detected.

Configure the TF display so the detection result is easy to see:

| Property | Value |
|---|---|
| Show Names | Checked |
| Show Axes | Checked |
| Show Arrows | Checked |
| Marker Scale | `0.2` initially; adjust as needed |
| Frame Timeout | `1` |

For a camera-centered view, Global Options → Fixed Frame can instead be set to
`camera_color_optical_frame`. Each detected tag then appears as a named set of
XYZ axes positioned and oriented relative to the RealSense color camera.

The TF display is the AprilTag pose result in RViz:

- Frame position represents the estimated tag translation.
- Frame axes represent the estimated tag orientation.
- The frame name contains the decoded ID, such as `tag36h11:2`.
- IDs 0, 1, and 2 can appear simultaneously when they are visible together.

RViz does not natively draw `AprilTagDetectionArray` corner boxes over the
Image display. The Image display shows the recorded RGB frame, while the TF
display shows the corresponding 3D detection result.

## Measure replay and detection rates

Run these commands one at a time:

```bash
ros2 topic hz /camera/camera/color/image_raw
```

```bash
ros2 topic hz /camera/camera/color/camera_info
```

```bash
ros2 topic hz /apriltag_rs/detections
```

```bash
ros2 topic hz /camera/camera/depth/color/points
```

Stop each measurement with `Ctrl+C`. Stopping `ros2 topic hz` does not stop
the bag player or detector because it is only a subscriber.

## Troubleshooting

### Detection topic does not exist

```bash
ros2 node list | grep apriltag
ros2 topic list | grep apriltag
```

Expected:

```text
/apriltag_rs/apriltag
/apriltag_rs/detections
```

If they are missing, Terminal 2 exited. Read its final error and restart the
detector.

### Detection messages are empty

```bash
ros2 topic echo /apriltag_rs/detections --once
```

If the result is `detections: []`, confirm in RViz that:

- The entire tag is visible in the recorded RealSense color image.
- It is a `tag36h11` marker.
- Its black square and surrounding white margin are unobstructed.
- It is flat, sharp, and not hidden by glare or motion blur.

### CameraInfo synchronization warning

Confirm both recorded streams are active:

```bash
ros2 topic hz /camera/camera/color/image_raw
```

```bash
ros2 topic hz /camera/camera/color/camera_info
```

Use only the RealSense image and its matching RealSense CameraInfo. Do not use
the Insta360 image with RealSense calibration.

### TF is missing

Check these conditions:

1. The detection message contains a tag rather than `detections: []`.
2. `pose_estimation_method` is `pnp`, not an empty string.
3. Terminal 1 uses `--clock`.
4. The detector, RViz, and `tf2_echo` use `use_sim_time:=true`.
5. The requested tag ID is currently visible.

### Shared-memory transport warning

This warning is usually nonfatal:

```text
RTPS_TRANSPORT_SHM Error: Failed init_port
```

ROS 2 normally falls back to UDP. If the process stays running and its topics
exist, continue using it.

### RViz image or point cloud is blank

- Confirm Terminal 1 is still running and not paused.
- Set the display reliability to `Best Effort`.
- Keep Fixed Frame set to `camera_link`.
- Verify the selected topic with `ros2 topic hz`.

## Quick-start summary

```text
Terminal 1
  ros2 bag play ... --clock --loop

Terminal 2
  apriltag_node reading the recorded RealSense image and CameraInfo

Terminal 3
  ros2 topic echo /apriltag_rs/detections

Terminal 4
  tf2_echo camera_color_optical_frame tag36h11:<id>

Terminal 5
  rviz2 with use_sim_time:=true
```

This reproduces RealSense AprilTag detection entirely from recorded bag data;
the physical RealSense camera is not required during replay.

## Optional cubemap AprilTag mode

The cubemap workflow detects tags in an Insta360 cubemap face without using
RealSense CameraInfo. It creates synchronized dummy CameraInfo messages, runs
2D AprilTag detection with pose estimation disabled, and publishes an annotated
image for RViz.

Start the default front-face workflow:

```bash
chmod +x scripts/start_cubemap_bag_apriltag.sh
chmod +x scripts/cubemap_apriltag_support.py
./scripts/start_cubemap_bag_apriltag.sh --check
./scripts/start_cubemap_bag_apriltag.sh
```

Select a different cubemap face:

```bash
./scripts/start_cubemap_bag_apriltag.sh \
  /home/fanchen/Desktop/rosbag2_2026_09_23-19_14_03 \
  right
```

Supported face names are `front`, `back`, `left`, `right`, and
`horizontal`.

The cubemap RViz view displays:

```text
/apriltag_cubemap/image_annotated
```

Green outlines and labels such as `tag36h11:2` show successful detections.
The label also includes the decision margin.

This mode provides tag IDs, centers, corners, and decision margins. It does not
provide valid tag TF, orientation, or distance because the synchronized
CameraInfo contains no calibrated camera matrix. Use the RealSense workflow
above when accurate 3D pose or distance is required.
