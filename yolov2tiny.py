import os
import sys
import pickle
import numpy as np
import tensorflow as tf


class YOLO_V2_TINY(object):

    def __init__(self, in_shape, weight_pickle, proc="cpu"):
        self.g = tf.Graph()
        config = tf.compat.v1.ConfigProto()
        config.gpu_options.allow_growth = True
        self.sess = tf.compat.v1.Session(config=config, graph=self.g)
        self.proc = proc
        self.weight_pickle = weight_pickle
        self.input_tensor, self.tensor_list = self.build_graph(in_shape)

    def _w_to_tensor(self, w, i, key_list):
        kernel = tf.convert_to_tensor(w[i]['kernel'], dtype=tf.float32)
        biases = tf.convert_to_tensor(w[i]['biases'], dtype=tf.float32)

        if ('moving_mean' in key_list) and ('moving_variance' in key_list) and ('gamma' in key_list):
            moving_mean = tf.convert_to_tensor(w[i]['moving_mean'], dtype=tf.float32)
            moving_variance = tf.convert_to_tensor(w[i]['moving_variance'], dtype=tf.float32)
            gamma = tf.convert_to_tensor(w[i]['gamma'], dtype=tf.float32)

        else:
            moving_mean = None
            moving_variance = None
            gamma = None

        return kernel, biases, moving_mean, moving_variance, gamma

    def build_graph(self, in_shape):
        #
        # This function builds a tensor graph. Once created,
        # it will be used to inference every frame.
        #
        # Your code from here. You may clear the comments.

        # Use self.g as a default graph. Refer to this API.
        ## https://www.tensorflow.org/api_docs/python/tf/Graph#as_default
        # Then you need to declare which device to use for tensor computation. The device info
        # is given from the command line argument and stored somewhere in this object.
        # In this project, you may choose CPU or GPU. Consider using the following API.
        ## https://www.tensorflow.org/api_docs/python/tf/Graph#device
        # Then you are ready to add tensors to the graph. According to the Yolo v2 tiny model,
        # build a graph and append the tensors to the returning list for computing intermediate
        # values. One tip is to start adding a placeholder tensor for the first tensor.
        # (Use bn_eps for the epsilon value of batch normalization layers.)

        # Construct computation graph, following the loaded weight structure
        tensor_list = list()
        with self.g.as_default():
            with tf.device('/'+self.proc):
                # Load weight parameters from a pickle file.
                with open(self.weight_pickle, 'rb') as h:
                    w = pickle.load(h, encoding='latin1')
                for i in range(len(w)):
                    print('Conv{}'.format(i))
                    for k in w[i].keys():
                        print('\tConv{}[{}]: {}'.format(i, k, w[i][k].shape))

                # Input placeholder
                input_tensor = tf.compat.v1.placeholder(tf.float32, shape=in_shape, name="input")

                alpha = 0.1
                bn_eps = 1e-5

                # Block 0
                kernel, biases, moving_mean, moving_variance, gamma = self._w_to_tensor(w, 0, ['kernel', 'biases', 'moving_mean', 'moving_variance', 'gamma'])
                c0 = tf.nn.conv2d(input=input_tensor, filters=kernel, strides=[1, 1, 1, 1], padding='SAME')
                b0 = tf.nn.bias_add(value=c0, bias=biases)
                n0 = tf.nn.batch_normalization(x=b0, mean=moving_mean, variance=moving_variance, offset=None, scale=gamma, variance_epsilon=bn_eps)
                r0 = tf.maximum(alpha * n0, n0)
                # r0 = tf.nn.leaky_relu(features=n0, alpha=alpha)
                m0 = tf.nn.max_pool2d(r0, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1], padding='SAME')

                # Block 1
                kernel, biases, moving_mean, moving_variance, gamma = self._w_to_tensor(w, 1, ['kernel', 'biases', 'moving_mean', 'moving_variance', 'gamma'])
                c1 = tf.nn.conv2d(input=m0, filters=kernel, strides=[1, 1, 1, 1], padding='SAME')
                b1 = tf.nn.bias_add(value=c1, bias=biases)
                n1 = tf.nn.batch_normalization(x=b1, mean=moving_mean, variance=moving_variance, offset=None, scale=gamma, variance_epsilon=bn_eps)
                r1 = tf.maximum(alpha * n1, n1)
                # r1 = tf.nn.leaky_relu(features=n1, alpha=alpha)
                m1 = tf.nn.max_pool2d(r1, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1], padding='SAME')

                # Block 2
                kernel, biases, moving_mean, moving_variance, gamma = self._w_to_tensor(w, 2, ['kernel', 'biases', 'moving_mean', 'moving_variance', 'gamma'])
                c2 = tf.nn.conv2d(input=m1, filters=kernel, strides=[1, 1, 1, 1], padding='SAME')
                b2 = tf.nn.bias_add(value=c2, bias=biases)
                n2 = tf.nn.batch_normalization(x=b2, mean=moving_mean, variance=moving_variance, offset=None, scale=gamma, variance_epsilon=bn_eps)
                r2 = tf.maximum(alpha * n2, n2)
                # r2 = tf.nn.leaky_relu(features=n2, alpha=alpha)
                m2 = tf.nn.max_pool2d(r2, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1], padding='SAME')

                # Block 3
                kernel, biases, moving_mean, moving_variance, gamma = self._w_to_tensor(w, 3, ['kernel', 'biases', 'moving_mean', 'moving_variance', 'gamma'])
                c3 = tf.nn.conv2d(input=m2, filters=kernel, strides=[1, 1, 1, 1], padding='SAME')
                b3 = tf.nn.bias_add(value=c3, bias=biases)
                n3 = tf.nn.batch_normalization(x=b3, mean=moving_mean, variance=moving_variance, offset=None, scale=gamma, variance_epsilon=bn_eps)
                r3 = tf.maximum(alpha * n3, n3)
                # r3 = tf.nn.leaky_relu(features=n3, alpha=alpha)
                m3 = tf.nn.max_pool2d(r3, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1], padding='SAME')

                # Block 4
                kernel, biases, moving_mean, moving_variance, gamma = self._w_to_tensor(w, 4, ['kernel', 'biases', 'moving_mean', 'moving_variance', 'gamma'])
                c4 = tf.nn.conv2d(input=m3, filters=kernel, strides=[1, 1, 1, 1], padding='SAME')
                b4 = tf.nn.bias_add(value=c4, bias=biases)
                n4 = tf.nn.batch_normalization(x=b4, mean=moving_mean, variance=moving_variance, offset=None, scale=gamma, variance_epsilon=bn_eps)
                r4 = tf.maximum(alpha * n4, n4)
                # r4 = tf.nn.leaky_relu(features=n4, alpha=alpha)
                m4 = tf.nn.max_pool2d(r4, ksize=[1, 2, 2, 1], strides=[1, 2, 2, 1], padding='SAME')

                # Block 5
                kernel, biases, moving_mean, moving_variance, gamma = self._w_to_tensor(w, 5, ['kernel', 'biases', 'moving_mean', 'moving_variance', 'gamma'])
                c5 = tf.nn.conv2d(input=m4, filters=kernel, strides=[1, 1, 1, 1], padding='SAME')
                b5 = tf.nn.bias_add(value=c5, bias=biases)
                n5 = tf.nn.batch_normalization(x=b5, mean=moving_mean, variance=moving_variance, offset=None, scale=gamma, variance_epsilon=bn_eps)
                r5 = tf.maximum(alpha * n5, n5)
                # r5 = tf.nn.leaky_relu(features=n5, alpha=alpha)
                m5 = tf.nn.max_pool2d(r5, ksize=[1, 2, 2, 1], strides=[1, 1, 1, 1], padding='SAME')

                # Block 6
                kernel, biases, moving_mean, moving_variance, gamma = self._w_to_tensor(w, 6, ['kernel', 'biases', 'moving_mean', 'moving_variance', 'gamma'])
                c6 = tf.nn.conv2d(input=m5, filters=kernel, strides=[1, 1, 1, 1], padding='SAME')
                b6 = tf.nn.bias_add(value=c6, bias=biases)
                n6 = tf.nn.batch_normalization(x=b6, mean=moving_mean, variance=moving_variance, offset=None, scale=gamma, variance_epsilon=bn_eps)
                r6 = tf.maximum(alpha * n6, n6)
                # r6 = tf.nn.leaky_relu(features=n6, alpha=alpha)

                # Block 7
                kernel, biases, moving_mean, moving_variance, gamma = self._w_to_tensor(w, 7, ['kernel', 'biases', 'moving_mean', 'moving_variance', 'gamma'])
                c7 = tf.nn.conv2d(input=r6, filters=kernel, strides=[1, 1, 1, 1], padding='SAME')
                b7 = tf.nn.bias_add(value=c7, bias=biases)
                n7 = tf.nn.batch_normalization(x=b7, mean=moving_mean, variance=moving_variance, offset=None, scale=gamma, variance_epsilon=bn_eps)
                r7 = tf.maximum(alpha * n7, n7)
                # r7 = tf.nn.leaky_relu(features=n7, alpha=alpha)

                # Block 8
                kernel, biases, _, _, _ = self._w_to_tensor(w, 8, ['kernel', 'biases'])
                c8 = tf.nn.conv2d(input=r7, filters=kernel, strides=[1, 1, 1, 1], padding='SAME')
                b8 = tf.nn.bias_add(value=c8, bias=biases)

                tensor_list += [c0, b0, n0, r0, m0]
                tensor_list += [c1, b1, n1, r1, m1]
                tensor_list += [c2, b2, n2, r2, m2]
                tensor_list += [c3, b3, n3, r3, m3]
                tensor_list += [c4, b4, n4, r4, m4]
                tensor_list += [c5, b5, n5, r5, m5]
                tensor_list += [c6, b6, n6, r6]
                tensor_list += [c7, b7, n7, r7]
                tensor_list += [c8, b8]

        # Return the start tensor and the list of all tensors.
        return input_tensor, tensor_list

    def inference(self, img):
        feed_dict = {self.input_tensor: img}
        out_tensors = self.sess.run(self.tensor_list, feed_dict)
        return out_tensors


#
# Codes belows are for postprocessing step. Do not modify. The postprocessing 
# function takes an input of a resulting tensor as an array to parse it to
# generate the label box positions. It returns a list of the positions which
# composed of a label, two coordinates of left-top and right-bottom of the box
# and its color.
#

def postprocessing(predictions, w0, h0):
    """
    :param predictions: (1, 125, 13, 13) numpy array
        Each grid cell corresponds to 125 channels, made up of the 5 bounding boxes predicted by the grid cell
        and the 25 data elements that describe each bounding box.
    :param w0: integer
        Original video width
    :param h0: integer
        Original video height
    :return: bbox_list: list of tuples (x, y, w, h, text), representing bbox of confidence > 0.25
        x, y: bbox position in global coordinate, in respect to original image
        w, h: bbox size in global coordinate, in respect to original image
        text: box representative text (i.e. semantic category)
    """

    n_classes = 20
    n_grid_cells = 13
    n_b_boxes = 5
    n_b_box_coord = 4

    # Names and colors for each class
    classes = ["aeroplane", "bicycle", "bird", "boat", "bottle", "bus", "car", "cat", "chair", "cow", "diningtable",
               "dog", "horse", "motorbike", "person", "pottedplant", "sheep", "sofa", "train", "tvmonitor"]
    colors = [(254.0, 254.0, 254), (239.88888888888889, 211.66666666666669, 127),
              (225.77777777777777, 169.33333333333334, 0), (211.66666666666669, 127.0, 254),
              (197.55555555555557, 84.66666666666667, 127), (183.44444444444443, 42.33333333333332, 0),
              (169.33333333333334, 0.0, 254), (155.22222222222223, -42.33333333333335, 127),
              (141.11111111111111, -84.66666666666664, 0), (127.0, 254.0, 254),
              (112.88888888888889, 211.66666666666669, 127), (98.77777777777777, 169.33333333333334, 0),
              (84.66666666666667, 127.0, 254), (70.55555555555556, 84.66666666666667, 127),
              (56.44444444444444, 42.33333333333332, 0), (42.33333333333332, 0.0, 254),
              (28.222222222222236, -42.33333333333335, 127), (14.111111111111118, -84.66666666666664, 0),
              (0.0, 254.0, 254), (-14.111111111111118, 211.66666666666669, 127)]

    # Pre-computed YOLOv2 shapes of the k=5 B-Boxes
    """ [p_w, p_h] for first bbox, [p_w, p_h] for second bbox, ... (distance in output cell space)
    """
    anchors = [1.08, 1.19, 3.42, 4.41, 6.63, 11.38, 9.42, 5.11, 16.62, 10.52]

    """ Image pixel distance per one output cell width / height
    """

    thresholded_predictions = []

    # IMPORTANT: reshape to have shape = [ 13 x 13 x (5 B-Boxes) x (4 Coords + 1 Obj score + 20 Class scores ) ]
    predictions = np.reshape(predictions, (13, 13, 5, 25))

    # IMPORTANT: Compute the coordinates and score of the B-Boxes by considering the parametrization of YOLOv2
    for row in range(n_grid_cells):
        for col in range(n_grid_cells):
            for b in range(n_b_boxes):

                tx, ty, tw, th, tc = predictions[row, col, b, :5]

                # IMPORTANT: (416 img size) / (13 grid cells) = 32!
                # YOLOv2 predicts parametrized coordinates that must be converted to full size
                # final_coordinates = parametrized_coordinates * 32.0 ( You can see other EQUIVALENT ways to do this...)
                """ Position in cell space -> Position in original video pixel space
                """
                center_x = (float(col) + sigmoid(tx)) * 32.0 * (w0 / 416)
                center_y = (float(row) + sigmoid(ty)) * 32.0 * (h0 / 416)

                """ Size in cell space -> Size in original video pixel space
                """
                roi_w = np.exp(tw) * anchors[2 * b + 0] * 32.0 * (w0 / 416)
                roi_h = np.exp(th) * anchors[2 * b + 1] * 32.0 * (h0 / 416)

                final_confidence = sigmoid(tc)

                # Find best class
                class_predictions = predictions[row, col, b, 5:]
                class_predictions = softmax(class_predictions)

                class_predictions = tuple(class_predictions)
                best_class = class_predictions.index(max(class_predictions))
                best_class_score = class_predictions[best_class]

                # Flip the coordinates on both axes
                left = int(center_x - (roi_w / 2.))
                right = int(center_x + (roi_w / 2.))
                top = int(center_y - (roi_h / 2.))
                bottom = int(center_y + (roi_h / 2.))

                if (final_confidence * best_class_score) > 0.3:
                    thresholded_predictions.append(
                        [[left, top, right, bottom], final_confidence * best_class_score, classes[best_class]])

    # Sort the B-boxes by their final score
    thresholded_predictions.sort(key=lambda tup: tup[1], reverse=True)

    # Non maximal suppression
    if len(thresholded_predictions) > 0:
        nms_predictions = non_maximal_suppression(thresholded_predictions, 0.3)
    else:
        nms_predictions = []

    label_boxes = []
    # Append B-Boxes
    for i in range(len(nms_predictions)):
        best_class_name = nms_predictions[i][2]
        lefttop = tuple(nms_predictions[i][0][0:2])
        rightbottom = tuple(nms_predictions[i][0][2:4])
        color = colors[classes.index(nms_predictions[i][2])]

        label_boxes.append((best_class_name, lefttop, rightbottom, color))

    return label_boxes


def iou(boxA, boxB):
    # boxA = boxB = [x1,y1,x2,y2]

    # Determine the coordinates of the intersection rectangle
    xA = max(boxA[0], boxB[0])
    yA = max(boxA[1], boxB[1])
    xB = min(boxA[2], boxB[2])
    yB = min(boxA[3], boxB[3])

    # Compute the area of intersection
    intersection_area = (xB - xA + 1) * (yB - yA + 1)

    # Compute the area of both rectangles
    boxA_area = (boxA[2] - boxA[0] + 1) * (boxA[3] - boxA[1] + 1)
    boxB_area = (boxB[2] - boxB[0] + 1) * (boxB[3] - boxB[1] + 1)

    # Compute the IOU
    iou = intersection_area / float(boxA_area + boxB_area - intersection_area)

    return iou


def non_maximal_suppression(thresholded_predictions, iou_threshold):
    nms_predictions = []

    # Add the best B-Box because it will never be deleted
    nms_predictions.append(thresholded_predictions[0])

    # For each B-Box (starting from the 2nd) check its iou with the higher score B-Boxes
    # thresholded_predictions[i][0] = [x1,y1,x2,y2]
    i = 1
    while i < len(thresholded_predictions):
        n_boxes_to_check = len(nms_predictions)
        # print('N boxes to check = {}'.format(n_boxes_to_check))
        to_delete = False

        j = 0
        while j < n_boxes_to_check:
            curr_iou = iou(thresholded_predictions[i][0], nms_predictions[j][0])
            if (curr_iou > iou_threshold):
                to_delete = True
            # print('Checking box {} vs {}: IOU = {} , To delete = {}'.format(thresholded_predictions[i][0],nms_predictions[j][0],curr_iou,to_delete))
            j = j + 1

        if to_delete == False:
            nms_predictions.append(thresholded_predictions[i])
        i = i + 1

    return nms_predictions


def sigmoid(x):
    return 1 / (1 + np.e ** -x)


def softmax(x):
    e_x = np.exp(x - np.max(x))
    return e_x / e_x.sum(axis=0)
