# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  ../../config/[common, curves],
  ../../primitives,
  ../../arithmetic,
  ../../arithmetic/assembly/[
    limbs_asm_mul_x86_adx_bmi2,
    limbs_asm_montmul_x86_adx_bmi2,
    limbs_asm_montred_x86_adx_bmi2
  ]


# ############################################################
#                                                            #
#             Assembly implementation of 𝔽p2                 #
#                                                            #
# ############################################################

static: doAssert UseASM_X86_64

# MULX/ADCX/ADOX
{.localPassC:"-madx -mbmi2".}
# Necessary for the compiler to find enough registers (enabled at -O1)
{.localPassC:"-fomit-frame-pointer".}

# No exceptions allowed
{.push raises: [].}

template c0*(a: array): auto =
  a[0]
template c1*(a: array): auto =
  a[1]

func has1extraBit(F: type Fp): bool =
  ## We construct extensions only on Fp (and not Fr)
  getSpareBits(F) >= 1

func has2extraBits(F: type Fp): bool =
  ## We construct extensions only on Fp (and not Fr)
  getSpareBits(F) >= 2

# 𝔽p2 squaring
# ------------------------------------------------------------

func sqrx2x_complex_asm_adx_bmi2*(
        r: var array[2, FpDbl],
        a: array[2, Fp]
      ) =
  ## Complex squaring on 𝔽p2
  # This specialized proc inlines all calls and avoids many ADX support checks.
  # and push/pop for paramater passing.

  var t0 {.noInit.}, t1 {.noInit.}: typeof(a.c0)

  when Fp.has1extraBit():
    t0.sumUnr(a.c1, a.c1)
    t1.sumUnr(a.c0, a.c1)
  else:
    t0.double(a.c1)
    t1.sum(a.c0, a.c1)

  r.c1.mul_asm_adx_bmi2_impl(t0, a.c0)
  t0.diff(a.c0, a.c1)
  r.c0.mul_asm_adx_bmi2_impl(t0, t1)

func sqrx_complex_sparebit_asm_adx_bmi2*(
        r: var array[2, Fp],
        a: array[2, Fp]
      ) =
  ## Complex squaring on 𝔽p2
  # This specialized proc inlines all calls and avoids many ADX support checks.
  # and push/pop for paramater passing.
  # Staying in 𝔽p and not using double-precision is faster for squaring

  static: doAssert Fp.has1extraBit()

  var v0 {.noInit.}, v1 {.noInit.}: typeof(r.c0)
  v0.diff(a.c0, a.c1)
  v1.sum(a.c0, a.c1)
  r.c1.mres.limbs.montMul_CIOS_sparebit_asm_adx_bmi2(a.c0.mres.limbs, a.c1.mres.limbs, Fp.fieldMod().limbs, Fp.getNegInvModWord())
  # aliasing: a unneeded now
  r.c1.double()
  r.c0.mres.limbs.montMul_CIOS_sparebit_asm_adx_bmi2(v0.mres.limbs, v1.mres.limbs, Fp.fieldMod().limbs, Fp.getNegInvModWord())

# 𝔽p2 multiplication
# ------------------------------------------------------------

func mulx2x_complex_asm_adx_bmi2*(
        r: var array[2, FpDbl],
        a, b: array[2, Fp]
      ) =
  ## Complex multiplication on 𝔽p2
  var D {.noInit.}: typeof(r.c0)
  var t0 {.noInit.}, t1 {.noInit.}: typeof(a.c0)

  r.c0.limbs2x.mul_asm_adx_bmi2_impl(a.c0.mres.limbs, b.c0.mres.limbs)
  D.limbs2x.mul_asm_adx_bmi2_impl(a.c1.mres.limbs, b.c1.mres.limbs)
  when Fp.has1extraBit():
    t0.sumUnr(a.c0, a.c1)
    t1.sumUnr(b.c0, b.c1)
  else:
    t0.sum(a.c0, a.c1)
    t1.sum(b.c0, b.c1)
  r.c1.limbs2x.mul_asm_adx_bmi2_impl(t0.mres.limbs, t1.mres.limbs)
  when Fp.has1extraBit():
    r.c1.diff2xUnr(r.c1, r.c0)
    r.c1.diff2xUnr(r.c1, D)
  else:
    r.c1.diff2xMod(r.c1, r.c0)
    r.c1.diff2xMod(r.c1, D)
  r.c0.diff2xMod(r.c0, D)

func mulx_complex_asm_adx_bmi2*(
        r: var array[2, Fp],
        a, b: array[2, Fp]
      ) =
  ## Complex multiplication on 𝔽p2
  var d {.noInit.}: array[2,doublePrec(Fp)]
  d.mulx2x_complex_asm_adx_bmi2(a, b)
  r.c0.mres.limbs.montRed_asm_adx_bmi2_impl(
    d.c0.limbs2x,
    Fp.fieldMod().limbs,
    Fp.getNegInvModWord(),
    Fp.has1extraBit()
  )
  r.c1.mres.limbs.montRed_asm_adx_bmi2_impl(
    d.c1.limbs2x,
    Fp.fieldMod().limbs,
    Fp.getNegInvModWord(),
    Fp.has1extraBit()
  )
