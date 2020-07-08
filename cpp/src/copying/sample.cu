/*
 * Copyright (c) 2020, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <curand.h>
#include <curand_kernel.h>
#include <cudf/column/column.hpp>
#include <cudf/column/column_factories.hpp>
#include <cudf/detail/gather.cuh>
#include <cudf/detail/gather.hpp>
#include <cudf/detail/nvtx/ranges.hpp>
#include <cudf/table/table.hpp>
#include <cudf/table/table_view.hpp>

#include <thrust/device_vector.h>
#include <thrust/random.h>
#include <thrust/random/uniform_int_distribution.h>
#include <thrust/shuffle.h>

namespace cudf {
namespace detail {

std::unique_ptr<table> sample(table_view const& input,
                              size_type const n,
                              row_multi_sampling multi_smpl,
                              long const seed,
                              rmm::mr::device_memory_resource* mr,
                              cudaStream_t stream)
{
  CUDF_EXPECTS(n >= 0, "expected number of samples should be non-negative");
  auto num_rows = input.num_rows();

  if ((n > num_rows) and (multi_smpl == row_multi_sampling::DISALLOWED)) {
    CUDF_FAIL("If n > number of rows, then multiple sampling of the same row should be allowed");
  }

  if (n == 0) return cudf::empty_like(input);

  if (multi_smpl == row_multi_sampling::ALLOWED) {
    auto RandomGen = [seed, num_rows] __device__(auto i) {
      thrust::default_random_engine rng(seed);
      thrust::uniform_int_distribution<size_type> dist{0, num_rows};
      rng.discard(i);
      return dist(rng);
    };

    auto begin =
      thrust::make_transform_iterator(thrust::counting_iterator<size_type>(0), RandomGen);
    auto end = thrust::make_transform_iterator(thrust::counting_iterator<size_type>(n), RandomGen);

    return detail::gather(input, begin, end, false, mr, stream);
  } else {
    auto rng_eng = thrust::random::default_random_engine(seed);
    auto gather_map =
      make_numeric_column(data_type{type_id::INT32}, num_rows, mask_state::UNALLOCATED, stream);
    auto gather_map_mutable_view = gather_map->mutable_view();
    // Shuffle all the row indices
    thrust::shuffle_copy(rmm::exec_policy(stream)->on(stream),
                         thrust::counting_iterator<size_type>(0),
                         thrust::counting_iterator<size_type>(num_rows),
                         gather_map_mutable_view.begin<size_type>(),
                         rng_eng);
    auto gather_map_view = gather_map->view();

    if (n != num_rows) {
      auto sliced_gather_map = cudf::slice(gather_map_view, {0, n})[0];
      return detail::gather(input,
                            sliced_gather_map.begin<size_type>(),
                            sliced_gather_map.end<size_type>(),
                            false,
                            mr,
                            stream);
    } else {
      return detail::gather(input,
                            gather_map_view.begin<size_type>(),
                            gather_map_view.end<size_type>(),
                            false,
                            mr,
                            stream);
    }
  }
}

}  // namespace detail

std::unique_ptr<table> sample(table_view const& input,
                              size_type const n,
                              row_multi_sampling multi_smpl,
                              long const seed,
                              rmm::mr::device_memory_resource* mr)
{
  CUDF_FUNC_RANGE();

  return detail::sample(input, n, multi_smpl, seed, mr);
}
}  // namespace cudf
