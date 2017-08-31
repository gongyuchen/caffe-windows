#include <algorithm>
#include <cfloat>
#include <vector>

#include "thrust/device_vector.h"

#include "caffe/layer.hpp"
#include "caffe/util/math_functions.hpp"
#include "caffe/layers/channel_scale_layer.hpp"

namespace caffe {

template <typename Dtype>
__global__ void kernel_channel_scale(const int num, const int channels, const int spatial_dim,
                                     Dtype alpha, const Dtype* data, const Dtype* norm_data,
                                     Dtype beta, Dtype* output_data) {
  CUDA_KERNEL_LOOP(index, num * channels * spatial_dim) {
    int n = index / channels / spatial_dim;
    int s = index % spatial_dim;
    output_data[index] = alpha * data[index] * norm_data[n * spatial_dim + s] + beta * output_data[index];
  }
}

template <typename Dtype>
__global__ void kernel_channel_sum(const int num, const int channels, const int spatial_dim,
                                   const Dtype* data, Dtype* sum_data) {
  CUDA_KERNEL_LOOP(index, num * spatial_dim) {
    int n = index / spatial_dim;
    int s = index % spatial_dim;
    Dtype sum = 0;
    for (int c = 0; c < channels; ++c) {
      sum += data[(n * channels + c) * spatial_dim + s];
    }
    sum_data[index] = sum;
  }
}

template <typename Dtype>
void ChannelScaleLayer<Dtype>::Forward_gpu(const vector<Blob<Dtype>*>& bottom,
    const vector<Blob<Dtype>*>& top) {
  const Dtype* bottom_data = bottom[0]->gpu_data();
  const Dtype* scale_data = bottom[1]->gpu_data();
  Dtype* top_data = top[0]->mutable_gpu_data();
  
  int num = bottom[0]->num();
  int channels = bottom[0]->channels();
  int spatial_dim = bottom[0]->height() * bottom[0]->width();
  // NOLINT_NEXT_LINE(whitespace/operators)
  kernel_channel_scale<Dtype> << <CAFFE_GET_BLOCKS(num*channels*spatial_dim),
    CAFFE_CUDA_NUM_THREADS >> >(num, channels, spatial_dim, Dtype(1), bottom_data, scale_data, Dtype(0), top_data);
}



template <typename Dtype>
void ChannelScaleLayer<Dtype>::Backward_gpu(const vector<Blob<Dtype>*>& top,
    const vector<bool>& propagate_down, const vector<Blob<Dtype>*>& bottom) {
  const Dtype* top_diff = top[0]->gpu_diff();
  const Dtype* bottom_data = bottom[0]->gpu_data();
  const Dtype* scale_data = bottom[1]->gpu_data();
  Dtype* bottom_diff = bottom[0]->mutable_gpu_diff();
  Dtype* scale_diff = bottom[1]->mutable_gpu_diff();

  int num = top[0]->num();
  int channels = top[0]->channels();
  int spatial_dim = bottom[0]->height() * bottom[0]->width();

  if (propagate_down[1]) {
    caffe_gpu_mul(bottom[0]->count(), top_diff, bottom_data, bottom_diff);
    // NOLINT_NEXT_LINE(whitespace/operators)
    kernel_channel_sum<Dtype> << <CAFFE_GET_BLOCKS(num*spatial_dim),
      CAFFE_CUDA_NUM_THREADS >> >(num, channels, spatial_dim, bottom_diff, scale_diff);
  }
  
  if (propagate_down[0]) {
    // NOLINT_NEXT_LINE(whitespace/operators)
    kernel_channel_scale<Dtype> << <CAFFE_GET_BLOCKS(num*channels*spatial_dim),
      CAFFE_CUDA_NUM_THREADS >> >(num, channels, spatial_dim, Dtype(1), top_diff, scale_data, Dtype(0), bottom_diff);
  }
}

INSTANTIATE_LAYER_GPU_FUNCS(ChannelScaleLayer);


}  // namespace caffe