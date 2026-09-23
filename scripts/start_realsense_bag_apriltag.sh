#!/usr/bin/env bash

set -Eeuo pipefail

readonly ros_setup="/opt/ros/jazzy/setup.bash"
readonly default_bag="/home/fanchen/Desktop/rosbag2_2026_09_23-19_14_03"
readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_dir="$(cd -- "${script_dir}/.." && pwd)"
readonly rviz_config="${repository_dir}/config/realsense_bag_apriltag.rviz"

mode="start"
bag_path="${default_bag}"

if [[ "${1:-}" == "--component" ]]; then
  mode="${2:?missing component name}"
  bag_path="${3:-${default_bag}}"
elif [[ "${1:-}" == "--check" ]]; then
  mode="check"
elif [[ -n "${1:-}" ]]; then
  bag_path="$1"
fi

source_ros() {
  if [[ ! -f "${ros_setup}" ]]; then
    printf 'ROS setup not found: %s\n' "${ros_setup}" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  set +u
  source "${ros_setup}"
  set -u
}

run_and_hold() {
  set +e
  "$@"
  local exit_code=$?
  set -e

  printf '\nProcess exited with status %d. Press Enter to close this window.\n' "${exit_code}"
  read -r _
  exit "${exit_code}"
}

preflight() {
  if [[ ! -d "${bag_path}" || ! -f "${bag_path}/metadata.yaml" ]]; then
    printf 'ROS 2 bag not found: %s\n' "${bag_path}" >&2
    exit 1
  fi

  if [[ ! -f "${rviz_config}" ]]; then
    printf 'RViz configuration not found: %s\n' "${rviz_config}" >&2
    exit 1
  fi

  if ! command -v gnome-terminal >/dev/null 2>&1; then
    printf 'gnome-terminal is required for the one-click launcher.\n' >&2
    exit 1
  fi

  source_ros
  ros2 pkg prefix apriltag_ros >/dev/null
  ros2 pkg prefix rviz2 >/dev/null
}

launch_component() {
  local title="$1"
  local component="$2"

  gnome-terminal --title="${title}" -- "${BASH_SOURCE[0]}" --component "${component}" "${bag_path}"
}

case "${mode}" in
  check)
    preflight
    printf 'Preflight passed. Bag, ROS packages, terminal, and RViz config are ready.\n'
    ;;

  start)
    preflight

    launch_component "1 - ROS bag playback" bag
    launch_component "2 - RealSense AprilTag detector" detector
    launch_component "3 - AprilTag detections" detections
    launch_component "4 - RViz AprilTag view" rviz

    printf 'Started bag playback, AprilTag detection, detection output, and RViz.\n'
    printf 'Close the four terminal windows and RViz to stop the workflow.\n'
    ;;

  bag)
    source_ros
    run_and_hold ros2 bag play "${bag_path}" --clock --loop
    ;;

  detector)
    source_ros
    sleep 3
    detector_command=(
      ros2 run apriltag_ros apriltag_node --ros-args
      -r __ns:=/apriltag_rs
      -r image_rect:=/camera/camera/color/image_raw
      -r camera_info:=/camera/camera/color/camera_info
      -p family:=36h11
      -p size:=0.05
      -p pose_estimation_method:=pnp
      -p qos_profile:=sensor_data
      -p detector.threads:=4
      -p detector.decimate:=1.0
      -p use_sim_time:=true
    )
    run_and_hold "${detector_command[@]}"
    ;;

  detections)
    source_ros
    sleep 5
    run_and_hold ros2 topic echo /apriltag_rs/detections
    ;;

  rviz)
    source_ros
    sleep 5
    run_and_hold rviz2 -d "${rviz_config}" --ros-args -p use_sim_time:=true
    ;;

  *)
    printf 'Unknown component: %s\n' "${mode}" >&2
    exit 2
    ;;
esac
