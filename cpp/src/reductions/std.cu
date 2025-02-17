/*
 * Copyright (c) 2019-2023, NVIDIA CORPORATION.
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

#include <cudf/detail/reduction_functions.hpp>
#include <cudf/dictionary/dictionary_column_view.hpp>
#include <reductions/compound.cuh>

#include <rmm/cuda_stream_view.hpp>

namespace cudf {
namespace reduction {

std::unique_ptr<cudf::scalar> standard_deviation(column_view const& col,
                                                 cudf::data_type const output_dtype,
                                                 size_type ddof,
                                                 rmm::cuda_stream_view stream,
                                                 rmm::mr::device_memory_resource* mr)
{
  // TODO: add cuda version check when the fix is available
#if !defined(__CUDACC_DEBUG__)
  using reducer =
    compound::detail::element_type_dispatcher<cudf::reduction::op::standard_deviation>;
  auto col_type =
    cudf::is_dictionary(col.type()) ? dictionary_column_view(col).keys().type() : col.type();
  return cudf::type_dispatcher(col_type, reducer(), col, output_dtype, ddof, stream, mr);
#else
  // workaround for bug 200529165 which causes compilation error only at device debug build
  // hopefully the bug will be fixed in future cuda version (still failing in 11.2)
  CUDF_FAIL("var/std reductions are not supported at debug build.");
#endif
}

}  // namespace reduction
}  // namespace cudf
