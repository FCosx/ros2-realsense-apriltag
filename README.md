  # ROS 2 RealSense AprilTag Detection and Distance Measurement

  This project uses ROS 2 Jazzy, an Intel RealSense D455F, `apriltag_ros`,
  and RViz to:

  - Stream color and depth images
  - Detect AprilTags
  - Estimate AprilTag position and orientation
  - Measure camera-to-tag distance
  - Visualize the color image, TF frames, and point cloud in RViz

  ## Hardware

  - Ubuntu laptop
  - Intel RealSense D455F
  - USB-C data cable
  - Printed `tag36h11` AprilTag
  - Current tag black-square size: 50 mm × 50 mm

  The tag must have a visible white margin. The configured tag size refers only
  to the outer black square, excluding the white margin.

  ## Software

  - Ubuntu 24.04
  - ROS 2 Jazzy
  - RealSense ROS wrapper
  - `apriltag_ros`
  - RViz 2

  ## Installation

  Source ROS:

  ```bash
  source /opt/ros/jazzy/setup.bash

  Install the required packages:

  sudo apt update

  sudo apt install \
    ros-jazzy-realsense2-camera \
    ros-jazzy-realsense2-description \
    ros-jazzy-apriltag-ros \
    ros-jazzy-rviz2 \
    ros-jazzy-rqt-image-view \
    ros-jazzy-tf2-tools

  To source ROS automatically in new terminals:

  echo 'source /opt/ros/jazzy/setup.bash' >> ~/.bashrc
  source ~/.bashrc

  ## Verify the RealSense Connection

  Connect the RealSense directly to a USB 3 port.

  lsusb | grep -i -E 'intel|realsense'
  lsusb -t

  The USB connection should report 5000M, 10000M, or another USB 3 speed,
  rather than 480M.

  Check the device:

  rs-enumerate-devices

  ## Terminal 1: Start the RealSense

  source /opt/ros/jazzy/setup.bash

  ros2 launch realsense2_camera rs_launch.py \
    enable_color:=true \
    enable_depth:=true \
    enable_sync:=true \
    align_depth.enable:=true \
    pointcloud.enable:=true \
    pointcloud.allow_no_texture_points:=true \
    rgb_camera.color_profile:=640x480x30 \
    depth_module.depth_profile:=640x480x30

  The RealSense publishes topics including:

  /camera/camera/color/image_raw
  /camera/camera/color/camera_info
  /camera/camera/depth/image_rect_raw
  /camera/camera/aligned_depth_to_color/image_raw
  /camera/camera/depth/color/points
  /tf_static

  Verify them:

  ros2 topic list | grep camera

  ## Terminal 2: Start AprilTag Detection

  For a 50 mm tag:

  source /opt/ros/jazzy/setup.bash

  ros2 run apriltag_ros apriltag_node --ros-args \
    -r __ns:=/apriltag_rs \
    -r image_rect:=/camera/camera/color/image_raw \
    -r camera_info:=/camera/camera/color/camera_info \
    -p family:=36h11 \
    -p size:=0.05 \
    -p qos_profile:=sensor_data \
    -p detector.threads:=4 \
    -p detector.decimate:=1.0

  For a 60 mm tag, use:

  -p size:=0.06

  The configured size must equal the measured width of the outer black square.

  ## Check AprilTag Detections

  ros2 topic echo /apriltag_rs/detections

  Example:

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

  Important fields:

  - family: AprilTag family
  - id: detected tag ID
  - hamming: corrected bit errors; zero is ideal
  - decision_margin: detection strength
  - centre: tag centre in image pixels
  - corners: four tag-corner pixel coordinates
  - homography: projective mapping between the tag and image

  ## Measure Detection Frequency

  Camera image frequency:

  ros2 topic hz /camera/camera/color/image_raw

  AprilTag detection frequency:

  ros2 topic hz /apriltag_rs/detections

  Point-cloud frequency:

  ros2 topic hz /camera/camera/depth/color/points

  The camera is configured for 30 FPS, but actual delivered rates depend on USB
  bandwidth, enabled processing filters, CPU performance, and subscriber load.

  ## Measure Tag Distance Using TF

  For tag ID 2:

  ros2 run tf2_ros tf2_echo \
    camera_color_optical_frame \
    'tag36h11:2'

  Example result:

  Translation: [0.019, -0.024, 0.239]

  In the camera optical frame:

  - x: horizontal offset
  - y: vertical offset
  - z: forward depth

  The straight-line distance is:

  distance = sqrt(x² + y² + z²)

  For the example:

  distance = sqrt(0.019² + (-0.024)² + 0.239²)
           ≈ 0.241 m

  The measured camera-to-tag-centre distance was therefore approximately
  24.1 cm.

  TF-based distance depends directly on the configured physical tag size.
  Changing a 60 mm tag to 50 mm requires changing size from 0.06 to 0.05.

  ## RViz Visualization

  Start RViz:

  rviz2

  Configure:

  ### Global Options

  Fixed Frame: camera_link

  ### Image display

  Add an Image display:

  Topic: /camera/camera/color/image_raw
  Reliability Policy: Best Effort

  ### PointCloud2 display

  Add a PointCloud2 display:

  Topic: /camera/camera/depth/color/points
  Reliability Policy: Best Effort
  Style: Points
  Size (Pixels): 2 or 3
  Color Transformer: RGB8
  Decay Time: 0

  If RGB coloring does not appear, temporarily select AxisColor.

  ### TF display

  Add a TF display to visualize:

  camera_link
  camera_color_optical_frame
  camera_depth_optical_frame
  tag36h11:2

  ## Save the RViz Configuration

  In RViz:

  File → Save Config As

  Save it inside the repository as:

  config/realsense_apriltag.rviz

  It can later be reopened with:

  rviz2 -d config/realsense_apriltag.rviz

  ## Runtime Architecture

  RealSense D455F
      │
      ├── Color image ────────────────┐
      ├── Color camera calibration ───┤
      ├── Aligned depth               │
      ├── Point cloud ───────────────► RViz
      └── Camera TF                   │
                                      │
                                      ▼
                                apriltag_ros
                                      │
                                      ├── /apriltag_rs/detections
                                      └── camera → tag TF

  ## Common Problems

  ### ros--package-name

  Cause: $ROS_DISTRO was empty.

  Fix:

  source /opt/ros/jazzy/setup.bash

  ### Camera already in use

  Example error:

  Pipeline handler in use by another process
  failed to acquire camera

  Find the process:

  sudo fuser -v /dev/video*

  Inspect and stop only the stale camera process:

  ps -fp <PID>
  kill <PID>

  ### No AprilTag detections

  Check whether the detector publishes empty arrays:

  ros2 topic echo /apriltag_rs/detections --once

  If the result is:

  detections: []

  the detector receives images but cannot recognize the marker.

  Check that:

  - The tag family is tag36h11
  - The complete black square and white margin are visible
  - The tag is flat
  - Transparent tape is not causing glare
  - The tag is not folded around a cube edge
  - The marker occupies a useful portion of the image
  - Lighting is bright and even
  - The print is sharp and high contrast

  ### Paper tag works but cube tag fails

  The tag needs a white quiet zone around the black square.

  Do not make the black tag exactly as large as the cube face. For a 60 mm cube
  face, a 45–50 mm black tag with a white margin is more reliable.

  ### Point cloud remains after stopping ros2 topic hz

  ros2 topic hz is only a subscriber. The RealSense node in Terminal 1 remains
  the point-cloud publisher.

  Disable point-cloud generation dynamically:

  ros2 param set /camera/camera pointcloud.enable false

  Enable it again:

  ros2 param set /camera/camera pointcloud.enable true

  ### RealSense configuration warning

  This warning is normally harmless:

  No valid configuration file found at ~/.realsense-config.json

  The driver loads its default settings.

  ## Useful Inspection Commands

  List topics and types:

  ros2 topic list -t

  Inspect publishers, subscribers, and QoS:

  ros2 topic info /apriltag_rs/detections --verbose

  Inspect the AprilTag node:

  ros2 node info /apriltag_rs/apriltag

  Read one detection:

  ros2 topic echo /apriltag_rs/detections --once

  Read the point-cloud frame:

  ros2 topic echo \
    /camera/camera/depth/color/points \
    --once --field header.frame_id

  ## Notes

  - Do not publish the RealSense serial number in a public repository.
  - Use a direct USB 3 connection when possible.
  - The RealSense supplies factory camera calibration.
  - The AprilTag size parameter affects TF pose scale.
  - RealSense depth and point-cloud distances do not depend on AprilTag size.
