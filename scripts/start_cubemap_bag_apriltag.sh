#!/usr/bin/env bash

set -Eeuo pipefail

readonly ros_setup="/opt/ros/jazzy/setup.bash"
readonly default_bag="/home/fanchen/Desktop/rosbag2_2026_09_23-19_14_03"
readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_dir="$(cd -- "${script_dir}/.." && pwd)"
readonly parameter_config="${repository_dir}/config/cubemap_apriltag.yaml"
readonly rviz_config="${repository_dir}/config/cubemap_bag_apriltag.rviz"
readonly support_script="${script_dir}/cubemap_apriltag_support.py"

mode="start"
bag_path="${default_bag}"
face="front"

if [[ "${1:-}" == "--component" ]]; then
  mode="${2:?missing component name}"
  bag_path="${3:-${default_bag}}"
  face="${4:-front}"
elif [[ "${1:-}" == "--check" ]]; then
  mode="check"
  face="${2:-front}"
elif [[ -n "${1:-}" ]]; then
  bag_path="$1"
  face="${2:-front}"
fi

case "${face}" in
  front|back|left|right|horizontal) ;;
  *)
    printf 'Invalid cubemap face: %s\n' "${face}" >&2
    printf 'Choose front, back, left, right, or horizontal.\n' >&2
    exit 2
    ;;
esac

readonly image_topic="/cubemap/${face}/image"
readonly camera_info_topic="/cubemap/${face}/camera_info"
readonly detections_topic="/apriltag_cubemap/detections"
readonly annotated_topic="/apriltag_cubemap/image_annotated"

source_ros() {
  if [[ ! -f "${ros_setup}" ]]; then
    printf 'ROS setup not found: %s\n' "${ros_setup}" >&2
    exit 1
  fi

  set +u
  # shellcheck disable=SC1090
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

  for required_file in "${parameter_config}" "${rviz_config}" "${support_script}"; do
    if [[ ! -f "${required_file}" ]]; then
      printf 'Required file not found: %s\n' "${required_file}" >&2
      exit 1
    fi
  done

  if ! command -v gnome-terminal >/dev/null 2>&1; then
    printf 'gnome-terminal is required for the one-click launcher.\n' >&2
    exit 1
  fi

  source_ros
  ros2 pkg prefix apriltag_ros >/dev/null
  ros2 pkg prefix rviz2 >/dev/null
  python3 -c 'import apriltag_msgs, cv2, cv_bridge, rclpy'
}

launch_component() {
  local title="$1"
  local component="$2"

  gnome-terminal --title="${title}" -- "${BASH_SOURCE[0]}" --component "${component}" "${bag_path}" "${face}"
}

case "${mode}" in
  check)
    preflight
    printf 'Cubemap preflight passed for face: %s\n' "${face}"
    ;;

  start)
    preflight
    launch_component "1 - ROS bag playback" bag
    launch_component "2 - Cubemap CameraInfo and overlay" support
    launch_component "3 - Cubemap AprilTag detector" detector
    launch_component "4 - Cubemap detections" detections
    launch_component "5 - Cubemap AprilTag RViz" rviz

    printf 'Started cubemap AprilTag detection for face: %s\n' "${face}"
    printf 'Close the five terminal windows and RViz to stop the workflow.\n'
    ;;

  bag)
    source_ros
    run_and_hold ros2 bag play "${bag_path}" --clock --loop
    ;;

  support)
    source_ros
    sleep 2
    support_command=(
      python3 "${support_script}"
      --image-topic "${image_topic}"
      --camera-info-topic "${camera_info_topic}"
      --detections-topic "${detections_topic}"
      --annotated-topic "${annotated_topic}"
    )
    run_and_hold "${support_command[@]}"
    ;;

  detector)
    source_ros
    sleep 4
    detector_command=(
      ros2 run apriltag_ros apriltag_node --ros-args
      -r __ns:=/apriltag_cubemap
      -r image_rect:="${image_topic}"
      --params-file "${parameter_config}"
    )
    run_and_hold "${detector_command[@]}"
    ;;

  detections)
    source_ros
    sleep 6
    run_and_hold ros2 topic echo "${detections_topic}"
    ;;

  rviz)
    source_ros
    sleep 7
    run_and_hold rviz2 -d "${rviz_config}" --ros-args -p use_sim_time:=true
    ;;

  *)
    printf 'Unknown component: %s\n' "${mode}" >&2
    exit 2
    ;;
esac
