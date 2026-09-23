#!/usr/bin/env python3

import argparse
from collections import OrderedDict

import cv2
import rclpy
from apriltag_msgs.msg import AprilTagDetectionArray
from cv_bridge import CvBridge
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo, Image


def stamp_key(message):
    stamp = message.header.stamp
    return stamp.sec, stamp.nanosec


class CameraInfoRelay(Node):
    def __init__(self, image_topic, camera_info_topic):
        super().__init__("cubemap_camera_info_relay")
        self.publisher = self.create_publisher(
            CameraInfo, camera_info_topic, qos_profile_sensor_data
        )
        self.subscription = self.create_subscription(
            Image, image_topic, self.image_callback, qos_profile_sensor_data
        )
        self.get_logger().info(
            f"Relaying synchronized dummy CameraInfo: "
            f"{image_topic} -> {camera_info_topic}"
        )

    def image_callback(self, image):
        info = CameraInfo()
        info.header = image.header
        info.width = image.width
        info.height = image.height
        self.publisher.publish(info)


class DetectionOverlay(Node):
    def __init__(self, image_topic, detections_topic, annotated_topic):
        super().__init__("cubemap_apriltag_overlay")
        self.bridge = CvBridge()
        self.image_cache = OrderedDict()
        self.maximum_cached_images = 30

        self.publisher = self.create_publisher(
            Image, annotated_topic, qos_profile_sensor_data
        )
        self.image_subscription = self.create_subscription(
            Image, image_topic, self.image_callback, qos_profile_sensor_data
        )
        self.detection_subscription = self.create_subscription(
            AprilTagDetectionArray,
            detections_topic,
            self.detection_callback,
            10,
        )
        self.get_logger().info(
            f"Publishing annotated detections: {annotated_topic}"
        )

    def image_callback(self, message):
        try:
            image = self.bridge.imgmsg_to_cv2(message, desired_encoding="bgr8")
        except Exception as error:
            self.get_logger().error(f"Image conversion failed: {error}")
            return

        self.image_cache[stamp_key(message)] = (message.header, image)
        while len(self.image_cache) > self.maximum_cached_images:
            self.image_cache.popitem(last=False)

    def detection_callback(self, message):
        cached = self.image_cache.pop(stamp_key(message), None)
        if cached is None:
            return

        header, image = cached

        for detection in message.detections:
            corners = [
                (int(round(point.x)), int(round(point.y)))
                for point in detection.corners
            ]

            for index in range(4):
                cv2.line(
                    image,
                    corners[index],
                    corners[(index + 1) % 4],
                    (0, 255, 0),
                    3,
                    cv2.LINE_AA,
                )

            centre = (
                int(round(detection.centre.x)),
                int(round(detection.centre.y)),
            )
            cv2.circle(image, centre, 5, (0, 0, 255), -1, cv2.LINE_AA)

            label = (
                f"{detection.family}:{detection.id} "
                f"margin={detection.decision_margin:.1f}"
            )
            label_origin = (corners[0][0], max(25, corners[0][1] - 10))
            cv2.putText(
                image,
                label,
                label_origin,
                cv2.FONT_HERSHEY_SIMPLEX,
                0.65,
                (0, 0, 0),
                4,
                cv2.LINE_AA,
            )
            cv2.putText(
                image,
                label,
                label_origin,
                cv2.FONT_HERSHEY_SIMPLEX,
                0.65,
                (0, 255, 0),
                2,
                cv2.LINE_AA,
            )

        annotated = self.bridge.cv2_to_imgmsg(image, encoding="bgr8")
        annotated.header = header
        self.publisher.publish(annotated)


def main():
    parser = argparse.ArgumentParser(
        description="Supply synchronized dummy CameraInfo and draw AprilTag detections."
    )
    parser.add_argument(
        "--image-topic", default="/cubemap/front/image"
    )
    parser.add_argument(
        "--camera-info-topic", default="/cubemap/front/camera_info"
    )
    parser.add_argument(
        "--detections-topic", default="/apriltag_cubemap/detections"
    )
    parser.add_argument(
        "--annotated-topic", default="/apriltag_cubemap/image_annotated"
    )
    arguments, ros_arguments = parser.parse_known_args()

    rclpy.init(args=ros_arguments)
    relay = CameraInfoRelay(
        arguments.image_topic, arguments.camera_info_topic
    )
    overlay = DetectionOverlay(
        arguments.image_topic,
        arguments.detections_topic,
        arguments.annotated_topic,
    )

    executor = MultiThreadedExecutor(num_threads=2)
    executor.add_node(relay)
    executor.add_node(overlay)

    try:
        executor.spin()
    except KeyboardInterrupt:
        pass
    finally:
        executor.shutdown()
        relay.destroy_node()
        overlay.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
