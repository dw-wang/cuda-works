// Homework 2
// Image Blurring
//
// In this homework we are blurring an image. To do this, imagine that we have
// a square array of weight values. For each pixel in the image, imagine that we
// overlay this square array of weights on top of the image such that the center
// of the weight array is aligned with the current pixel. To compute a blurred
// pixel value, we multiply each pair of numbers that line up. In other words, we
// multiply each weight with the pixel underneath it. Finally, we add up all of the
// multiplied numbers and assign that value to our output for the current pixel.
// We repeat this process for all the pixels in the image.

// To help get you started, we have included some useful notes here.

//****************************************************************************

// For a color image that has multiple channels, we suggest separating
// the different color channels so that each color is stored contiguously
// instead of being interleaved. This will simplify your code.

// That is instead of RGBARGBARGBARGBA... we suggest transforming to three
// arrays (as in the previous homework we ignore the alpha channel again):
//  1) RRRRRRRR...
//  2) GGGGGGGG...
//  3) BBBBBBBB...
//
// The original layout is known an Array of Structures (AoS) whereas the
// format we are converting to is known as a Structure of Arrays (SoA).

// As a warm-up, we will ask you to write the kernel that performs this
// separation. You should then write the "meat" of the assignment,
// which is the kernel that performs the actual blur. We provide code that
// re-combines your blurred results for each color channel.

//****************************************************************************

// You must fill in the gaussian_blur kernel to perform the blurring of the
// inputChannel, using the array of weights, and put the result in the outputChannel.

// Here is an example of computing a blur, using a weighted average, for a single
// pixel in a small image.
//
// Array of weights:
//
//  0.0  0.2  0.0
//  0.2  0.2  0.2
//  0.0  0.2  0.0
//
// Image (note that we align the array of weights to the center of the box):
//
//    1  2  5  2  0  3
//       -------
//    3 |2  5  1| 6  0       0.0*2 + 0.2*5 + 0.0*1 +
//      |       |
//    4 |3  6  2| 1  4   ->  0.2*3 + 0.2*6 + 0.2*2 +   ->  3.2
//      |       |
//    0 |4  0  3| 4  2       0.0*4 + 0.2*0 + 0.0*3
//       -------
//    9  6  5  0  3  9
//
//         (1)                         (2)                 (3)
//
// A good starting place is to map each thread to a pixel as you have before.
// Then every thread can perform steps 2 and 3 in the diagram above
// completely independently of one another.

// Note that the array of weights is square, so its height is the same as its width.
// We refer to the array of weights as a filter, and we refer to its width with the
// variable filterWidth.

//****************************************************************************

// Your homework submission will be evaluated based on correctness and speed.
// We test each pixel against a reference solution. If any pixel differs by
// more than some small threshold value, the system will tell you that your
// solution is incorrect, and it will let you try again.

// Once you have gotten that working correctly, then you can think about using
// shared memory and having the threads cooperate to achieve better performance.

//****************************************************************************

// Also note that we've supplied a helpful debugging function called checkCudaErrors.
// You should wrap your allocation and copying statements like we've done in the
// code we're supplying you. Here is an example of the unsafe way to allocate
// memory on the GPU:
//
// cudaMalloc(&d_red, sizeof(unsigned char) * numRows * numCols);
//
// Here is an example of the safe way to do the same thing:
//
// checkCudaErrors(cudaMalloc(&d_red, sizeof(unsigned char) * numRows * numCols));
//
// Writing code the safe way requires slightly more typing, but is very helpful for
// catching mistakes. If you write code the unsafe way and you make a mistake, then
// any subsequent kernels won't compute anything, and it will be hard to figure out
// why. Writing code the safe way will inform you as soon as you make a mistake.

// Finally, remember to free the memory you allocate at the end of the function.

//****************************************************************************

#include "utils.h"
#include <algorithm>
#include <math.h>


#define BLOCKSIZE_X 16
#define BLOCKSIZE_Y 16

// Clamp to boundary function
__device__
void clamp(int &index, int end) {
 index = (index < 0 ? 0 : (index > end ? end : index));
}

__global__
void gaussian_blur(const unsigned char* const inputChannel,
                   unsigned char* const outputChannel,
                   int numRows, int numCols,
                   const float* const filter, const int filterWidth)
{
  
  // NOTE: Be sure to compute any intermediate results in floating point
  // before storing the final result as unsigned char.

  // NOTE: Be careful not to try to access memory that is outside the bounds of
  // the image. You'll want code that performs the following check before accessing
  // GPU memory:
  //
  size_t idx_col = blockIdx.x * blockDim.x + threadIdx.x;
  size_t idx_row = blockIdx.y * blockDim.y + threadIdx.y;
  
  if ( idx_col >= numCols ||idx_row >= numRows )
  {
       return;
  }
  
  // NOTE: If a thread's absolute position 2D position is within the image, but some of
  // its neighbors are outside the image, then you will need to be extra careful. Instead
  // of trying to read such a neighbor value from GPU memory (which won't work because
  // the value is out of bounds), you should explicitly clamp the neighbor values you read
  // to be within the bounds of the image. If this is not clear to you, then please refer
  // to sequential reference solution for the exact clamping semantics you should follow.
  
  float result = 0.f;
  for (int filter_r = -filterWidth/2; filter_r <= filterWidth/2; filter_r++){
    for (int filter_c = -filterWidth/2; filter_c <= filterWidth/2; filter_c++) {
      // Find the global image position for this filter position and clamp to boundary
      // int image_r = min(max(static_cast<int>(idx_row) + filter_r, 0), numRows-1);
      // int image_c = min(max(static_cast<int>(idx_col) + filter_c, 0), numCols-1);
      int image_r = static_cast<int>(idx_row) + filter_r;
      clamp(image_r, numRows-1);
      int image_c = static_cast<int>(idx_col) + filter_c;
      clamp(image_c, numCols-1);

      float image_value = static_cast<float>(inputChannel[image_r * numCols + image_c]);
      float filter_value = filter[(filter_r + filterWidth/2) * filterWidth 
	      + filter_c + filterWidth/2];

      result += image_value * filter_value;
    }
  }
  outputChannel[idx_row * numCols + idx_col] = result;
}

// This kernel computes the same convolution operation as the above  gaussian_blur() function,
// but uses more efficient memory access by taking advantage of shared memory.
__global__
void gaussian_blur_shared_mem(const unsigned char* const inputChannel,
		              unsigned char* const outputChannel,
			      int numRows, int numCols,
			      const float* const filter, const int filterWidth) {
  // Get thread position
  size_t idx_col = blockIdx.x * blockDim.x + threadIdx.x;
  size_t idx_row = blockIdx.y * blockDim.y + threadIdx.y;

  // Bound checking
  if (idx_col >= numCols || idx_row >= numRows) return;
  
  /************** Copy data to shared memory *************/
  // Declare shared memory array including halo points
  const int RADIUS = filterWidth/2;
  const int numCols_sh = blockDim.x + 2*RADIUS;
  extern __shared__ unsigned char shared_data[];

  // Copy blockDim.x * blockDim.y internal values to shared memory
  size_t global_thread_idx = idx_row * numCols + idx_col;
  size_t thread_pos_in_sh_r = threadIdx.y + RADIUS;
  size_t thread_pos_in_sh_c = threadIdx.x + RADIUS;
  shared_data[thread_pos_in_sh_r * numCols_sh + thread_pos_in_sh_c] 
	                        = inputChannel[global_thread_idx];

  // Copy top and bottom halo points
  if (threadIdx.y < RADIUS) {
    // Top
    int halo_top_r = idx_row - RADIUS;
    clamp(halo_top_r, numRows-1);
    shared_data[threadIdx.y * numCols_sh + thread_pos_in_sh_c] 
	    = inputChannel[halo_top_r * numCols + idx_col];
    // Bottom
    int halo_bot_r = idx_row + blockDim.y;
    clamp(halo_bot_r, numRows-1);
    shared_data[(thread_pos_in_sh_r+blockDim.y) * numCols_sh + thread_pos_in_sh_c]
	    = inputChannel[halo_bot_r * numCols + idx_col];
  }
  // Copy left and right halo points
  if (threadIdx.x < RADIUS) {
    // Left
    int halo_left_c = idx_col - RADIUS;
    clamp(halo_left_c, numCols-1);
    shared_data[thread_pos_in_sh_r * numCols_sh + threadIdx.x]
	    = inputChannel[idx_row * numCols + halo_left_c];
    // Right
    int halo_right_c = idx_col + blockDim.x;
    clamp(halo_right_c, numCols - 1);
    shared_data[thread_pos_in_sh_r * numCols_sh + thread_pos_in_sh_c + blockDim.x]
	    = inputChannel[idx_row * numCols + halo_right_c];
  }
  // Copy corner halo points
  if (threadIdx.x < RADIUS && threadIdx.y < RADIUS) {
    // Clamp to boundary
    int halo_upper_r = idx_row - RADIUS;
    int halo_lower_r = idx_row + blockDim.y;
    int halo_left_c = idx_col - RADIUS;
    int halo_right_c = idx_col + blockDim.x;
    clamp(halo_upper_r, numRows-1);
    clamp(halo_lower_r, numRows-1);
    clamp(halo_left_c, numCols-1);
    clamp(halo_right_c, numCols-1);

    // Upper-left corner
    shared_data[threadIdx.y * numCols_sh + threadIdx.x] 
	    = inputChannel[halo_upper_r * numCols + halo_left_c];

    // Lower-right corner
    shared_data[(thread_pos_in_sh_r+blockDim.y) * numCols_sh + thread_pos_in_sh_c + blockDim.x]
	    = inputChannel[halo_lower_r * numCols + halo_right_c];

    // Upper-right corner
    shared_data[threadIdx.y * numCols_sh + thread_pos_in_sh_c + blockDim.x]
	    = inputChannel[halo_upper_r * numCols + halo_right_c];

    // Lower-left corner
    shared_data[(thread_pos_in_sh_r+blockDim.y) * numCols_sh + threadIdx.x]
	    = inputChannel[halo_lower_r * numCols + halo_left_c];
  }

  // Synchronize to ensure all shared data is loaded
  __syncthreads();

  float result = 0.f;
  for (int filter_r = -RADIUS; filter_r < RADIUS; filter_r++) {
    for (int filter_c = -RADIUS; filter_c < RADIUS; filter_c++) {
      size_t image_idx_in_sh_r = thread_pos_in_sh_r + filter_r;
      size_t image_idx_in_sh_c = thread_pos_in_sh_c + filter_c;
      
      float image_value = shared_data[image_idx_in_sh_r * numCols_sh + image_idx_in_sh_c];
      float filter_value = filter[(filter_r+RADIUS) * filterWidth + filter_c + RADIUS];

      result += image_value * filter_value;
    }
  }
  outputChannel[idx_row * numCols + idx_col] = result;
}

//This kernel takes in an image represented as a uchar4 and splits
//it into three images consisting of only one color channel each
__global__
void separateChannels(const uchar4* const inputImageRGBA,
                      int numRows,
                      int numCols,
                      unsigned char* const redChannel,
                      unsigned char* const greenChannel,
                      unsigned char* const blueChannel)
{
  // 
  //
  // NOTE: Be careful not to try to access memory that is outside the bounds of
  // the image. You'll want code that performs the following check before accessing
  // GPU memory:

  size_t idx_col = blockIdx.x * blockDim.x + threadIdx.x;
  size_t idx_row = blockIdx.y * blockDim.y + threadIdx.y;

  if ( idx_col >= numCols || idx_row >= numRows )
  {
      return;
  }

  // Get the color channels at idx
  size_t idx = idx_row * numCols + idx_col;
  uchar4 rgba = inputImageRGBA[idx];

  // Separate color channels
  redChannel[idx] = rgba.x;
  greenChannel[idx] = rgba.y;
  blueChannel[idx] = rgba.z;
}

//This kernel takes in three color channels and recombines them
//into one image.  The alpha channel is set to 255 to represent
//that this image has no transparency.
__global__
void recombineChannels(const unsigned char* const redChannel,
                       const unsigned char* const greenChannel,
                       const unsigned char* const blueChannel,
                       uchar4* const outputImageRGBA,
                       int numRows,
                       int numCols)
{
  const int2 thread_2D_pos = make_int2( blockIdx.x * blockDim.x + threadIdx.x,
                                        blockIdx.y * blockDim.y + threadIdx.y);

  const int thread_1D_pos = thread_2D_pos.y * numCols + thread_2D_pos.x;

  //make sure we don't try and access memory outside the image
  //by having any threads mapped there return early
  if (thread_2D_pos.x >= numCols || thread_2D_pos.y >= numRows)
    return;

  unsigned char red   = redChannel[thread_1D_pos];
  unsigned char green = greenChannel[thread_1D_pos];
  unsigned char blue  = blueChannel[thread_1D_pos];

  //Alpha should be 255 for no transparency
  uchar4 outputPixel = make_uchar4(red, green, blue, 255);

  outputImageRGBA[thread_1D_pos] = outputPixel;
}

unsigned char *d_red, *d_green, *d_blue;
float         *d_filter;

void allocateMemoryAndCopyToGPU(const size_t numRowsImage, const size_t numColsImage,
                                const float* const h_filter, const size_t filterWidth)
{

  //allocate memory for the three different channels
  //original
  checkCudaErrors(cudaMalloc(&d_red,   sizeof(unsigned char) * numRowsImage * numColsImage));
  checkCudaErrors(cudaMalloc(&d_green, sizeof(unsigned char) * numRowsImage * numColsImage));
  checkCudaErrors(cudaMalloc(&d_blue,  sizeof(unsigned char) * numRowsImage * numColsImage));

  //
  //Allocate memory for the filter on the GPU
  //Use the pointer d_filter that we have already declared for you
  //You need to allocate memory for the filter with cudaMalloc
  //be sure to use checkCudaErrors like the above examples to
  //be able to tell if anything goes wrong
  //IMPORTANT: Notice that we pass a pointer to a pointer to cudaMalloc
  checkCudaErrors(cudaMalloc(&d_filter, sizeof(float) * filterWidth * filterWidth));

  //
  //Copy the filter on the host (h_filter) to the memory you just allocated
  //on the GPU.  cudaMemcpy(dst, src, numBytes, cudaMemcpyHostToDevice);
  //Remember to use checkCudaErrors!
  checkCudaErrors(cudaMemcpy(d_filter, h_filter, sizeof(float) * filterWidth * filterWidth, cudaMemcpyHostToDevice));
}

void your_gaussian_blur(const uchar4 * const h_inputImageRGBA, uchar4 * const d_inputImageRGBA,
                        uchar4* const d_outputImageRGBA, const size_t numRows, const size_t numCols,
                        unsigned char *d_redBlurred, 
                        unsigned char *d_greenBlurred, 
                        unsigned char *d_blueBlurred,
                        const int filterWidth)
{
  // Set reasonable block size (i.e., number of threads per block)
  const dim3 blockSize(BLOCKSIZE_X, BLOCKSIZE_Y, 1);

  //
  //Compute correct grid size (i.e., number of blocks per kernel launch)
  //from the image size and and block size.
  const dim3 gridSize(numCols/blockSize.x + 1, numRows/blockSize.y + 1, 1);

  // Launch a kernel for separating the RGBA image into different color channels
  separateChannels<<<gridSize, blockSize>>>(d_inputImageRGBA, numRows, numCols, d_red, d_green, d_blue);

  // Call cudaDeviceSynchronize(), then call checkCudaErrors() immediately after
  // launching your kernel to make sure that you didn't make any mistakes.
  cudaDeviceSynchronize(); checkCudaErrors(cudaGetLastError());

  // Call convolution kernel here 3 times, once for each color channel.
  if (!USE_SHARED_MEM) {
    gaussian_blur<<<gridSize, blockSize>>>(d_red, d_redBlurred, numRows, numCols, d_filter, filterWidth);
    gaussian_blur<<<gridSize, blockSize>>>(d_green, d_greenBlurred, numRows, numCols, d_filter, filterWidth);
    gaussian_blur<<<gridSize, blockSize>>>(d_blue, d_blueBlurred, numRows, numCols, d_filter, filterWidth);
  } else {
    size_t sh_mem_size = (BLOCKSIZE_X + filterWidth - 1) * (BLOCKSIZE_Y + filterWidth - 1) * sizeof(unsigned char);
    gaussian_blur_shared_mem<<<gridSize, blockSize, sh_mem_size>>>(d_red, d_redBlurred, numRows, numCols, d_filter, filterWidth);
    gaussian_blur_shared_mem<<<gridSize, blockSize, sh_mem_size>>>(d_green, d_greenBlurred, numRows, numCols, d_filter, filterWidth);
    gaussian_blur_shared_mem<<<gridSize, blockSize, sh_mem_size>>>(d_blue, d_blueBlurred, numRows, numCols, d_filter, filterWidth);
  }

  // Again, call cudaDeviceSynchronize(), then call checkCudaErrors() immediately after
  // launching your kernel to make sure that you didn't make any mistakes.
  cudaDeviceSynchronize(); checkCudaErrors(cudaGetLastError());

  // Now we recombine your results. We take care of launching this kernel for you.
  //
  // NOTE: This kernel launch depends on the gridSize and blockSize variables,
  // which you must set yourself.
  recombineChannels<<<gridSize, blockSize>>>(d_redBlurred,
                                             d_greenBlurred,
                                             d_blueBlurred,
                                             d_outputImageRGBA,
                                             numRows,
                                             numCols);
  cudaDeviceSynchronize(); checkCudaErrors(cudaGetLastError());

}


// Free all the memory that we allocated
// make sure you free any arrays that you allocated
void cleanup() {
  checkCudaErrors(cudaFree(d_red));
  checkCudaErrors(cudaFree(d_green));
  checkCudaErrors(cudaFree(d_blue));
  checkCudaErrors(cudaFree(d_filter));
}
