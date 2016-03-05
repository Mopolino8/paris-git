!================================================================================================
!=================================================================================================
! Paris-0.1
!
! Free surface extensions
! written by Daniel Fuster
!
! This program is free software; you can redistribute it and/or
! modify it under the terms of the GNU General Public License as
! published by the Free Software Foundation; either version 2 of the
! License, or (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the GNU
! General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program; if not, write to the Free Software
! Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
! 02111-1307, USA.  
!=================================================================================================

MODULE module_mgsolver

CONTAINS
    
subroutine get_residual(A,p,L,norm,error_L1norm)
  use module_grid
  use module_BC
  implicit none
  include 'mpif.h'
  real(8) :: A(is:,js:,ks:,:), p(imin:,jmin:,kmin:,:)
  real(8), intent(out) :: error_L1norm
  integer, intent(in)  :: norm
  integer :: i,j,k,L

  error_L1norm = 0.d0

  do k=ks,ke; do j=js,je; do i=is,ie
      A(i,j,k,8) = A(i,j,k,8)     - A(i,j,k,7)*p(i,j,k,1)    + &
        A(i,j,k,1)*p(i-1,j,k,1) + A(i,j,k,2)*p(i+1,j,k,1)  + &
        A(i,j,k,3)*p(i,j-1,k,1) + A(i,j,k,4)*p(i,j+1,k,1)  + &
        A(i,j,k,5)*p(i,j,k-1,1) + A(i,j,k,6)*p(i,j,k+1,1) 
    error_L1norm = error_L1norm + abs(A(i,j,k,8))**norm
  enddo; enddo; enddo

end subroutine get_residual

subroutine coarse_fine_interp(pc,pf,imin1,jmin1,kmin1)
  use module_grid
  use module_BC
    implicit none
    integer :: imin1,jmin1,kmin1
    real(8) :: pc(imin1:,jmin1:,kmin1:,:), pf(imin:,jmin:,kmin:,:)
    integer :: i,j,k,is1,js1,ks1
    
    is1=imin1+Ng; js1=jmin1+Ng; ks1=kmin1+Ng
    !interpolation from coarse level
    do i=is,ie; do j=js,je; do k=ks,ke
      pc(2*(i-is)+is1,  2*(j-js)+js1,  2*(k-ks)+ks1,1)   = pf(i,j,k,1)
      pc(2*(i-is)+is1+1,2*(j-js)+js1,  2*(k-ks)+ks1,1)   = pf(i,j,k,1)
      pc(2*(i-is)+is1,  2*(j-js)+js1+1,2*(k-ks)+ks1,1)   = pf(i,j,k,1)
      pc(2*(i-is)+is1+1,2*(j-js)+js1+1,2*(k-ks)+ks1,1)   = pf(i,j,k,1)
      pc(2*(i-is)+is1,  2*(j-js)+js1,  2*(k-ks)+ks1+1,1) = pf(i,j,k,1)
      pc(2*(i-is)+is1+1,2*(j-js)+js1,  2*(k-ks)+ks1+1,1) = pf(i,j,k,1)
      pc(2*(i-is)+is1,  2*(j-js)+js1+1,2*(k-ks)+ks1+1,1) = pf(i,j,k,1)
      pc(2*(i-is)+is1+1,2*(j-js)+js1+1,2*(k-ks)+ks1+1,1) = pf(i,j,k,1)
    enddo; enddo; enddo

end subroutine coarse_fine_interp

subroutine coarse_from_fine(Af,Ac,is1,js1,ks1)
  use module_grid
  use module_BC
    implicit none
    integer :: is1,js1,ks1
    integer :: i,j,k
    real(8) :: Ac(is1:,js1:,ks1:,:), Af(is:,js:,ks:,:)

    Ac(:,:,:,8) = 0.d0
    DO i=is,ie; DO j=js,je; DO k=ks,ke
      Ac(is1+(i-is)/2, js1+(j-js)/2, ks1+(k-ks)/2, 8) = &
      Ac(is1+(i-is)/2, js1+(j-js)/2, ks1+(k-ks)/2, 8) + Af(i,j,k,8)
    ENDDO; ENDDO; ENDDO

end subroutine coarse_from_fine

subroutine fill_coefficients(Af, Ac, is1, js1, ks1)
  use module_grid
  use module_BC
  implicit none
  integer :: i,j,k,is1,js1,ks1
  real(8) :: Ac(is:,js:,ks:,:), Af(is1:,js1:,ks1:,:)

    DO k=ks,ke; DO j=js,je; DO i=is,ie
        Ac(i,j,k,:) =                          &
                Af(2*(i-is)+is1,  2*(j-js)+js1,  2*(k-ks)+ks1,:) + &
                Af(2*(i-is)+is1+1,2*(j-js)+js1,  2*(k-ks)+ks1,:) + &
                Af(2*(i-is)+is1,  2*(j-js)+js1+1,2*(k-ks)+ks1,:) + &
                Af(2*(i-is)+is1+1,2*(j-js)+js1+1,2*(k-ks)+ks1,:) + &
                Af(2*(i-is)+is1,  2*(j-js)+js1,  2*(k-ks)+ks1+1,:) + &
                Af(2*(i-is)+is1+1,2*(j-js)+js1,  2*(k-ks)+ks1+1,:) + &
                Af(2*(i-is)+is1,  2*(j-js)+js1+1,2*(k-ks)+ks1+1,:) + &
                Af(2*(i-is)+is1+1,2*(j-js)+js1+1,2*(k-ks)+ks1+1,:) 
     ENDDO; ENDDO; ENDDO

end subroutine fill_coefficients

subroutine NewSolverMG(A,p,maxError,beta,maxit,it,ierr)
  use module_grid
  use module_BC
  implicit none
  include 'mpif.h'
  real(8), dimension(imin:imax,jmin:jmax,kmin:kmax), intent(inout) :: p
  real(8), dimension(is:ie,js:je,ks:ke,8), intent(in) :: A
  TYPE equation
    real(8), ALLOCATABLE :: K(:,:,:,:)
  END TYPE equation
  TYPE(equation), ALLOCATABLE :: DataMG(:), pMG(:), EMG(:)
  real(8), intent(in) :: beta, maxError
  integer, intent(in) :: maxit
  integer, intent(out) :: it, ierr
  integer :: indextmp(3)
  real(8) :: tres2, resMax
  integer :: i,j,k,L,n, Level, ncycle, nrelax=2, Ld(3), nd(3)
  integer :: is1, js1, ks1, imin1, jmin1, kmin1
  integer :: nL(3)
  integer :: req(12),sta(MPI_STATUS_SIZE,12)
  logical :: mask(imin:imax,jmin:jmax,kmin:kmax)
  integer, parameter :: norm=1, relaxtype=1

  nd(1) = ie-is+1; nd(2) = je-js+1; nd(3) = ke-ks+1
  IF (IAND (nd(1), nd(1)-1).NE.0) STOP 'multigrid requires 2^n+1 nodes per direction'
  IF (IAND (nd(2), nd(2)-1).NE.0) STOP 'multigrid requires 2^n+1 nodes per direction'
  IF (IAND (nd(3), nd(3)-1).NE.0) STOP 'multigrid requires 2^n+1 nodes per direction'

  Ld(:) = int(log(float(nd(:)))/log(2.d0))

  indextmp(1) = ie; indextmp(2) = je; indextmp(3) = ke

  L = minval(Ld(:))
  call MPI_ALLREDUCE(L, L, 1, MPI_INTEGER, MPI_MIN, MPI_Comm_Cart, ierr) 

  ALLOCATE (DataMG(L)); ALLOCATE (pMG(L)); ALLOCATE (EMG(L))

  DO i=L,1,-1
      nL(:) = nd(:)/2**(L-i)
      ALLOCATE(DataMG(i)%K(nL(1),nL(2),nL(3),8))
      nL(:) = nd(:)/2**(L-i)+2*Ng
      ALLOCATE(pMG(i)%K(nL(1),nL(2),nL(3),1)) 
      ALLOCATE(EMG(i)%K(nL(1),nL(2),nL(3),1)) 
      DataMG(i)%K = 0.d0
      pMG(i)%K    = 0.d0
      EMG(i)%K    = 0.d0
  enddo

  do k=ks,ke; do j=js,je; do i=is,ie
      DataMG(L)%K(i-is+1,j-js+1,k-ks+1,:) = A(i,j,k,:) !fine level
  enddo; enddo; enddo

 !filling coarse levels
  DO Level=L-1,1,-1
    nL(:) = nd(:)/2**(L-Level)
    call update_bounds(nL)
    is1=coords(1)*nd(1)/2**(L-Level-1)+1+Ng
    js1=coords(2)*nd(2)/2**(L-Level-1)+1+Ng
    ks1=coords(3)*nd(3)/2**(L-Level-1)+1+Ng
    call fill_coefficients(DataMG(Level+1)%K,DataMG(Level)%K,is1,js1,ks1)
  ENDDO

  !compute residual at the finest level
  pMG(L)%K(:,:,:,1)    = p
  call update_bounds(nd)
  call get_residual(DataMG(L)%K,pMG(L)%K,L,norm,resMax)
  pMG(L)%K = 0.d0

  !-------------
  DO ncycle=1,maxit,1
  DO Level=L,2,-1

    pMG(Level)%K = 0.d0  !now pMG is the error
    nL(:) = nd(:)/2**(L-Level)
    call update_bounds(nL)
    
    DO i=1,nrelax
        call relax_step(DataMG(Level)%K,pMG(Level)%K(:,:,:,1),beta,Level)
    ENDDO
   
    call get_residual(DataMG(Level)%K,pMG(Level)%K,Level,norm,resMax)

    is1=coords(1)*nd(1)/2**(L-Level+1)+1+Ng
    js1=coords(2)*nd(2)/2**(L-Level+1)+1+Ng
    ks1=coords(3)*nd(3)/2**(L-Level+1)+1+Ng
    call coarse_from_fine(DataMG(Level)%K,DataMG(Level-1)%K,is1,js1,ks1) !projection at the next level

  ENDDO

  call relax_step(DataMG(2)%K,pMG(2)%K(:,:,:,1),beta,2)

  DO Level=3,L,1

    nL(:) = nd(:)/2**(L-Level+1)
    call update_bounds(nL)
    imin1=coords(1)*nd(1)/2**(L-Level)+1
    jmin1=coords(2)*nd(2)/2**(L-Level)+1
    kmin1=coords(3)*nd(3)/2**(L-Level)+1
    call coarse_fine_interp(EMG(Level)%K,pMG(Level-1)%K,imin1,jmin1,kmin1) !interpolation from coarse level
    nL(:) = nd(:)/2**(L-Level)
    call update_bounds(nL)
    call apply_BC_MG(EMG(Level)%K(:,:,:,1),Level)

    call get_residual(DataMG(Level)%K,EMG(Level)%K,Level,norm,resMax) !new residual
    pMG(Level)%K = pMG(Level)%K + EMG(Level)%K

    EMG(Level)%K = 0.d0  !initial guess of the error
    DO i=1,nrelax
      call relax_step(DataMG(Level)%K,EMG(Level)%K(:,:,:,1),beta,Level)
    ENDDO
    pMG(Level)%K = pMG(Level)%K + EMG(Level)%K

    call get_residual(DataMG(Level)%K,EMG(Level)%K,Level,norm,resMax)
  ENDDO

  p = p + pMG(L)%K(:,:,:,1)
  
  call MPI_ALLREDUCE(resMax, tres2, 1, MPI_DOUBLE_PRECISION, MPI_SUM, MPI_Comm_Cart, ierr) 
  if(norm==2) tres2=sqrt(tres2*dble(Nx*Ny*Nz))/dble(Nx*Ny*Nz)
  if (tres2<maxError) exit

  ENDDO

  call update_bounds(nd) !restore default values (MG finished)

  !free memory
  DO i=1,L
      DEALLOCATE(DataMG(i)%K) 
      DEALLOCATE(pMG(i)%K) 
      DEALLOCATE(EMG(i)%K) 
  ENDDO
  DEALLOCATE(DataMG) 
  DEALLOCATE(pMG) 
  DEALLOCATE(EMG) 

  if(it==maxit+1 .and. rank==0) write(*,*) 'Warning: LinearSolver reached maxit: ||res||: ',tres2

end subroutine NewSolverMG

subroutine write_sol(p)
  use module_grid
  use module_BC
  implicit none
  include 'mpif.h'
  integer :: i,j,k
  real(8), dimension(imin:imax,jmin:jmax,kmin:kmax), intent(inout) :: p

  !debugging
  if (rank==0) then
  OPEN(201, FILE="it_solution.dat")
  do k=ks,ke; do j=js,je; do i=is,ie
      write(201,*) x(i),y(j),z(k),p(i,j,k)
  enddo; enddo; enddo
  CLOSE(201)
  else
  OPEN(201, FILE="it_solution_1.dat")
  do k=ks,ke; do j=js,je; do i=is,ie
      write(201,*) x(i),y(j),z(k),p(i,j,k)
  enddo; enddo; enddo
  CLOSE(201)
  endif
end subroutine write_sol

END MODULE module_mgsolver
