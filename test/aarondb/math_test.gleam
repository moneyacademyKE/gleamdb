import aarondb/math
import gleeunit/should

pub fn math_cosine_similarity_test() {
  // Same length, non-zero
  let a = [1.0, 0.0, -1.0]
  let b = [1.0, 0.0, 1.0]
  let assert Ok(res) = math.cosine_similarity(a, b)
  should.equal(res, 0.0)
  // orthogonal

  let c = [2.0, 2.0]
  let d = [2.0, 2.0]
  let assert Ok(res2) = math.cosine_similarity(c, d)
  // floating point approximation to 1.0
  let is_close_to_one = res2 >. 0.999 && res2 <. 1.001
  should.be_true(is_close_to_one)

  // Different length
  should.be_error(math.cosine_similarity([1.0], [1.0, 2.0]))

  // Zero magnitude
  should.be_error(math.cosine_similarity([0.0, 0.0], [1.0, 1.0]))
}
