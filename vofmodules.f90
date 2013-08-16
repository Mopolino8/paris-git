!=================================================================================================
!=================================================================================================
! Paris-0.1
! Extended from Code: FTC3D2011 (Front Tracking Code for 3D simulations)
! and Surfer. 
! 
! Authors: Sadegh Dabiri, Gretar Tryggvason
! author for VOF extenstions Stephane Zaleski (zaleski@dalembert.upmc.fr) 
! Contact: sdabiri@gmail.com
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
! module_VOF: Contains definition of variables for the Volume of Fluid interface tracking.
!-------------------------------------------------------------------------------------------------
module module_VOF
  use module_grid
  use module_IO
  use module_tmpvar
  implicit none
  real(8), dimension(:,:,:), allocatable :: cvof ! VOF tracer variable
  real(8) :: A_h = 2d0  ! For initialisation 
  character(20) :: vofbdry_cond(3),test_type,vof_advect
  integer :: parameters_read=0
  logical :: test_heights = .false.  
  logical :: test_curvature = .false.  
  logical :: test_curvature_2D = .false.  
  logical :: test_HF = .false.
contains
!=================================================================================================
!=================================================================================================
!------------------------------------------------------------------------
  subroutine linfunc(field,a1,a2)
    implicit none
    real(8), dimension(imin:imax,jmin:jmax,kmin:kmax), intent(out) :: field
    real(8) :: a1,a2
    field = cvof*(a2-a1)+a1
  end subroutine linfunc
!=================================================================================================

  subroutine ReadVOFParameters
    use module_flow
    use module_BC
    implicit none
    include 'mpif.h'
    integer ierr,in
    logical file_is_there
    namelist /vofparameters/ vofbdry_cond,test_type,VOF_advect
    in=31
    call MPI_COMM_RANK(MPI_COMM_WORLD, rank, ierr)
    inquire(file='inputvof',exist=file_is_there)
    open(unit=in, file='inputvof', status='old', action='read', iostat=ierr)
    if (file_is_there) then
       if(ierr == 0) then
          read(UNIT=in,NML=vofparameters)
          if(rank==0) write(out,*)'VOF parameters read successfully'
       else
          print *, 'rank=',rank,' has error ',ierr,' opening file inputsolids'
       endif
    else
       if (rank == 0) STOP "ReadVOFParameters: no 'inputvof' file."
    endif
    close(in)
  end subroutine ReadVOFParameters
!
  subroutine initialize_VOF
    implicit none
    include 'mpif.h'
    integer :: ierr
    call ReadVOFParameters
! Check grid
    if(read_x.or.read_y.or.read_z) then
       if((xform.ne.0.d0).or.(yform.ne.0.d0).or.(zform.ne.0.d0)) then
          if (rank == 0) print *, "VOF does not yet work with variable grids"
          call MPI_Finalize(ierr)
          stop
       endif
    endif
    allocate(cvof(imin:imax,jmin:jmax,kmin:kmax))
    cvof = 0.D0
    if(test_type=='uniform_advection') then
       test_heights = .false.
    else if(test_type=='height_test') then
       test_heights = .true.
    else if(test_type=='curvature_test') then
       test_curvature = .true.
    else if(test_type=='curvature_test2D') then
       test_curvature_2D = .true.
    else
       stop 'unknown initialization'
    endif
    test_HF = test_heights .or. test_curvature .or. test_curvature_2D
   end subroutine initialize_VOF
!=================================================================================================
   subroutine initconditions_VOF()
     use module_hello
     use module_flow
     use module_BC
     use module_2phase

     implicit none
     include 'mpif.h'
     integer :: i,j,k,ib, ierr, irank, req(12),sta(MPI_STATUS_SIZE,12)
     real(8) :: my_ave
     integer :: ngh=2
     real(8) :: ls,kappa
     integer :: IndexCurv
     logical :: test=.false.
     real(8) :: shift 

     test = test_heights .or.test_curvature_2D  ! add other tests ...
      if(numbubble > 0.and..not.test) then 
         du = - 2.d6  ! Initialize du with a large negative value
         do ib=1,numBubble
            do i=imin,imax
               do j=jmin,jmax
                  do k=kmin,kmax 
                     ls = rad(ib)**2 - ((x(i)-xc(ib))**2+(y(j)-yc(ib))**2+(z(k)-zc(ib))**2)
                     ! update level-set function when the new value is larger 
                     ! final geometry is the union of indivdual bubbles. 
                     du(i,j,k) = MAX(ls,du(i,j,k))
                  enddo
               enddo
            enddo
         enddo
         i = imax-imin+1
         j = jmax-jmin+1
         k = kmax-kmin+1
         call levelset2vof(du,cvof,i,j,k)
! TEMPORARY
!         ib = 1
!         do i=is,ie
!            do j=js,je
!               do k=ks,ke
!                  if ( cvof(i,j,k) > 0.d0 .and. cvof(i,j,k) < 1.d0 )      &
!                  call cal_cvof(x(i),y(j),z(k),xc(ib),yc(ib),zc(ib),1.d0/dble(Nx),1.d0/dble(Ny),1.d0/dble(Nz),rad(ib),3,cvof(i,j,k))
!               end do
!            end do
!         end do
! END TEMPORARY
         call ghost_x(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
         call ghost_y(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
         call ghost_z(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
         call setVOFBC(cvof)
      else if(test_heights) then
         do i=imin,imax
            do j=jmin,jmax
               do k=kmin,kmax 
                  du(i,j,k) =   - z(k) + zlength/2.d0  + A_h*dx(nx/2)*cos(2.*3.14159*x(i)/xlength) 
               enddo
            enddo
         enddo
         i = imax-imin+1
         j = jmax-jmin+1
         k = kmax-kmin+1
         call levelset2vof(du,cvof,i,j,k)
         call ghost_x(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
         call ghost_y(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
         call ghost_z(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
         call setVOFBC(cvof)
      else if(test_curvature_2D) then
         du = - 2.d6  ! Initialize du with a large negative value
         shift = 0.2d0
         ib=1
         do i=imin,imax
            do j=jmin,jmax
               do k=kmin,kmax
                  if ( z(k) <= zc(ib)-shift ) then
                     ls = rad(ib)**2 - ((x(i)-xc(ib))**2+(y(j)-yc(ib))**2+(z(k)-(zc(ib)-shift))**2) 
                  else if ( z(k) >= zc(ib)+shift ) then 
                     ls = rad(ib)**2 - ((x(i)-xc(ib))**2+(y(j)-yc(ib))**2+(z(k)-(zc(ib)+shift))**2) 
                  else 
                     ls = rad(ib)**2 - ((x(i)-xc(ib))**2+(y(j)-yc(ib))**2) !+(z(k)-zc(ib))**2)
                  end if ! x(i)
!                  ls = rad(ib)**2 - ((x(i)-xc(ib))**2+(y(j)-yc(ib))**2+(z(k)-zc(ib))**2)
                  du(i,j,k) = MAX(ls,du(i,j,k))
               enddo
            enddo
         enddo
         i = imax-imin+1
         j = jmax-jmin+1
         k = kmax-kmin+1
         call levelset2vof(du,cvof,i,j,k)
! TEMPORARY
         do i=imin,imax
            do j=jmin,jmax
               do k=kmin,kmax
                  if ( cvof(i,j,k) > 0.d0 .and. cvof(i,j,k) < 1.d0      &
                  .and.z(k) > zc(ib)-shift.and. z(k) < zc(ib)+shift )   &
                  call cal_cvof(x(i),y(j),z(k),xc(ib),yc(ib),zc(ib),1.d0/dble(Nx),1.d0/dble(Ny),1.d0/dble(Nz),rad(ib),2,cvof(i,j,k))
               end do
            end do
         end do
! END TEMPORARY
         call ghost_x(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
         call ghost_y(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
         call ghost_z(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
         call setVOFBC(cvof)
      else
         cvof=0.d0
         if(rank==0) print *, "Warning: trivial VOF field."
      end if
! TEMPORARY
      contains
   subroutine cal_cvof(x1,y1,z1,x0,y0,z0,xw,yw,zw,r,dimflag,c)
      implicit none

      real(8), intent(in)  :: x1,y1,z1,x0,y0,z0,xw,yw,zw,r
      integer, intent(in)  :: dimflag 
      real(8), intent(out) :: c

      integer :: i,j,k,ni,nj,nk,n
      real(8) :: dx,dy,dz,dv,xi,yi,zi,rad,cf,csum

      n = 100
      ni=n;nj=n;nk=n
      if (dimflag == 2) nk=1
      dx=xw/dble(ni)
      dy=yw/dble(nj)
      dz=zw/dble(nk)
      dv=dx*dy*dz

      csum = 0.d0
      do i=1,ni; do j=1,nj; do k=1,nk
         xi = x1-xw/2.d0+(dble(i)-0.5d0)*dx
         yi = y1-yw/2.d0+(dble(j)-0.5d0)*dy
         zi = z1-zw/2.d0+(dble(k)-0.5d0)*dz

         cf = 0.d0
         if ( dimflag ==  2 ) then
            rad = sqrt((xi-x0)**2 + (yi-y0)**2)
            if ( rad < r ) cf = 1.d0
         else if ( dimflag == 3 ) then
            rad = sqrt((xi-x0)**2 + (yi-y0)**2 + (zi-z0)**2)
            if ( rad < r ) cf = 1.d0
         end if ! dimflag
         csum = csum + dv*cf 
      end do; end do; end do
      c = csum/(xw*yw*zw)
   end subroutine cal_cvof
! END TEMPORARY

    end subroutine initconditions_VOF
!=================================================================================================
  subroutine c_mask(cbinary)
    implicit none
    real(8), dimension(imin:imax,jmin:jmax,kmin:kmax), intent(out) :: cbinary

    where (cvof > 0.5d0)
       cbinary = 1.d0
    elsewhere
       cbinary = 0.d0
    end where
  end subroutine c_mask
!=================================================================================================
  subroutine vofsweeps(tswap)
    use module_BC
    use module_flow
    use module_tmpvar
    implicit none
    include 'mpif.h'
    integer, intent(in) :: tswap
    integer :: req(48),sta(MPI_STATUS_SIZE,48)
    integer :: ngh=2, ierr

    if (VOF_advect=='Dick_Yue') call c_mask(work(:,:,:,2))
    if (MOD(tswap,3) .eq. 0) then
       call swp(w,cvof,work(:,:,:,1),work(:,:,:,2),work(:,:,:,3),3)
       call ghost_x(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_y(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_z(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)

       call swp(u,cvof,work(:,:,:,1),work(:,:,:,2),work(:,:,:,3),1)
       call ghost_x(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_y(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_z(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)

       call swp(v,cvof,work(:,:,:,1),work(:,:,:,2),work(:,:,:,3),2)
       call ghost_x(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_y(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_z(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
    elseif (MOD(tswap,2) .eq. 0) then
       call swp(v,cvof,work(:,:,:,1),work(:,:,:,2),work(:,:,:,3),2)
       call ghost_x(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_y(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_z(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)

       call swp(w,cvof,work(:,:,:,1),work(:,:,:,2),work(:,:,:,3),3)
       call ghost_x(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_y(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_z(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)

       call swp(u,cvof,work(:,:,:,1),work(:,:,:,2),work(:,:,:,3),1)
       call ghost_x(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_y(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_z(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
    else 
       call swp(u,cvof,work(:,:,:,1),work(:,:,:,2),work(:,:,:,3),1)
       call ghost_x(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_y(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_z(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)

       call swp(v,cvof,work(:,:,:,1),work(:,:,:,2),work(:,:,:,3),2)
       call ghost_x(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_y(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_z(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)

       call swp(w,cvof,work(:,:,:,1),work(:,:,:,2),work(:,:,:,3),3)
       call ghost_x(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_y(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
       call ghost_z(cvof,ngh,req(1:4)); call MPI_WAITALL(4,req(1:4),sta(:,1:4),ierr)
    endif
  end subroutine vofsweeps
!=================================================================================================
! subroutine SetVOFBC: Sets the VOF fraction boundary condition
!-------------------------------------------------------------------------------------------------
  subroutine SetVOFBC(c)
    use module_grid
    implicit none
    include 'mpif.h'
    real(8), dimension(imin:imax,jmin:jmax,kmin:kmax), intent(inout) :: c

    if(vofbdry_cond(1)=='wet') then
       if(coords(1)==0    ) then
          c(is-1,:,:)=1.0
          c(is-2,:,:)=1.0
       endif
       if(coords(1)==nPx-1) then
          c(ie+1,:,:)=1.0
          c(ie+2,:,:)=1.0
       endif
    elseif (vofbdry_cond(1)=='90deg') then
       stop '90deg not implemented'
    endif

    if(vofbdry_cond(2)=='wet') then
       if(coords(2)==0    ) then
          c(:,js-1,:)=1.0
          c(:,js-2,:)=1.0
       endif
       if(coords(2)==nPy-1) then
          c(:,je+1,:)=1.0
          c(:,je+2,:)=1.0
       endif
    elseif (vofbdry_cond(2)=='90deg') then
       stop '90deg not implemented'
    endif

    if(vofbdry_cond(3)=='wet')then
       if(coords(3)==0    ) then
          c(:,:,ks-1)=1.0
          c(:,:,ks-2)=1.0
       endif
       if(coords(3)==nPz-1) then
          c(:,:,ke+1)=1.0
          c(:,:,ke+2)=1.0
       endif
    elseif (vofbdry_cond(2)=='90deg') then
       stop '90deg not implemented'
    endif

  end subroutine SetVOFBC
!=================================================================================================
end module module_vof

!-------------------------------------------------------------------------------------------------
module module_output_vof
  use module_IO
  use module_flow
  use module_grid
  use module_solid
  use module_vof
  implicit none
  integer :: vof_opened=0;
contains
  subroutine append_VOF_visit_file(rootname)
    implicit none
    character(*) :: rootname
    integer prank
    if(rank.ne.0) stop 'rank.ne.0 in append_VOF'
    if(vof_opened==0) then
       OPEN(UNIT=88,FILE='vof.visit')
       write(88,10) nPdomain
10     format('!NBLOCKS ',I4)
       vof_opened=1
    endif

    do prank=0,NpDomain-1
       write(88,11) rootname//TRIM(int2text(prank,padding))//'.vtk'
 11 format(A)
    enddo
  end subroutine  append_VOF_visit_file

  subroutine close_VOF_visit_file()
    close(88)
  end subroutine close_VOF_visit_file

  subroutine output_VOF(nf,i1,i2,j1,j2,k1,k2)
    implicit none
    integer ::nf,i1,i2,j1,j2,k1,k2,i,j,k
    character(len=30) :: rootname
    rootname=trim(out_path)//'/VTK/VOF'//TRIM(int2text(nf,padding))//'-'
    if(rank==0) call append_VOF_visit_file(TRIM(rootname))

    OPEN(UNIT=8,FILE=TRIM(rootname)//TRIM(int2text(rank,padding))//'.vtk')
    write(8,10)
    write(8,11) time
    write(8,12)
    write(8,13)
    write(8,14)i2-i1+1,j2-j1+1,k2-k1+1
    write(8,15)(i2-i1+1)*(j2-j1+1)*(k2-k1+1)
10  format('# vtk DataFile Version 2.0')
11  format('grid, time ',F16.8)
12  format('ASCII')
13  format('DATASET STRUCTURED_GRID')
14  format('DIMENSIONS ',I5,I5,I5)
15  format('POINTS ',I17,' float' )

    do k=k1,k2; do j=j1,j2; do i=i1,i2;
      write(8,320) x(i),y(j),z(k)
    enddo; enddo; enddo
320 format(e14.5,e14.5,e14.5)

    write(8,16)(i2-i1+1)*(j2-j1+1)*(k2-k1+1)
    write(8,17)'VOF'
    write(8,18)
16  format('POINT_DATA ',I17)
17  format('SCALARS ',A20,' float 1')
18  format('LOOKUP_TABLE default')

    do k=k1,k2; do j=j1,j2; do i=i1,i2;
      write(8,210) cvof(i,j,k)
    enddo; enddo; enddo
210 format(e14.5)
310 format(e14.5,e14.5,e14.5)
    close(8)
end subroutine output_VOF
!-------------------------------------------------------------------------------------------------
!=================================================================================================
end module module_output_vof
!
subroutine swp(us,c,vof1,vof2,vof3,d)
  use module_vof
  implicit none
  real (8)  , dimension(imin:imax,jmin:jmax,kmin:kmax), intent(in) :: us
  integer, intent(in) :: d
  real (8)  , dimension(imin:imax,jmin:jmax,kmin:kmax), intent(inout) :: c,vof1,vof2,vof3
  if (VOF_advect=='Dick_Yue') then
     call swpr(us,c,vof1,vof2,vof3,d)
  elseif (VOF_advect=='CIAM') then
     call swpz(us,c,vof1,vof2,vof3,d)
  else
     STOP "*** unknown vof scheme"
  endif
end subroutine swp

!  Implements the CIAM advection method of Jie Li. 
! 
! ****** 1 ******* 2 ******* 3 ******* 4 ******* 5 ******* 6 ******* 7 *
! split advection of the interface along the x (d=1), y (d=2) and z (d=3)
! direction
! ****** 1 ******* 2 ******* 3 ******* 4 ******* 5 ******* 6 ******* 7 *
subroutine swpz(us,c,vof1,vof2,vof3,d)
  !***
  use module_grid
  use module_flow
  use module_vof
  implicit none
  integer i,j,k,invx,invy,invz
  real (8)  , dimension(imin:imax,jmin:jmax,kmin:kmax), intent(in) :: us
  integer, intent(in) :: d
  real (8)  , dimension(imin:imax,jmin:jmax,kmin:kmax), intent(inout) :: c,vof1,vof2,vof3
  real(8) dmx,dmy,dmz,mm1,mm2
  real(8) a1,a2,alpha,al3d,fl3d
  real(8) mxyz(3),stencil3x3(-1:1,-1:1,-1:1)
  integer i0,j0,k0
  intrinsic dmax1,dmin1
  !***
  if(ng.lt.2) stop "wrong ng"
  do k=ks-1,ke+1
     do j=js-1,je+1
        do i=is-1,ie+1
           if (d.eq.1) then
              a2 = us(i,j,k)*dt/dxh(i)
              a1 = us(i-1,j,k)*dt/dxh(i-1)
           elseif (d.eq.2) then
              a2 = us(i,j,k)*dt/dyh(j)
              a1 = us(i,j-1,k)*dt/dyh(j-1)
           elseif (d.eq.3) then
              a2 = us(i,j,k)*dt/dzh(k)
              a1 = us(i,j,k-1)*dt/dzh(k-1)
           endif
           !***
           !     3 cases: 1: default (c=0. and fluxes=0.); 2: c=1.; 3:c>0.
           !***
           vof1(i,j,k) = 0.0d0
           vof2(i,j,k) = 0.0d0
           vof3(i,j,k) = 0.0d0

           ! we need to introduce full/empty flags

           if (c(i,j,k) .eq. 1.0d0) then
              vof1(i,j,k) = dmax1(-a1,0.d0)
              vof2(i,j,k) = 1.d0 - dmax1(a1,0.d0) + dmin1(a2,0.d0)
              vof3(i,j,k) = dmax1(a2,0.d0)

           else if (c(i,j,k) .gt. 0.d0) then
              !***
              !     (1) normal vector: dmx,dmy,dmz, and |dmx|+|dmy|+|dmz| = 1.
              !     (2) dmx,dmy,dmz>0.
              !     (3) get alpha;               (4) back to original plane;
              !     (5) lagrangian advection;    (6) get fluxes
              !*(1)*

              do i0=-1,1; do j0=-1,1; do k0=-1,1
                 stencil3x3(i0,j0,k0) = c(i+i0,j+j0,k+k0)
              enddo;enddo;enddo
              call mycs(stencil3x3,mxyz)
              dmx = mxyz(1)
              dmy = mxyz(2)
              dmz = mxyz(3)
              !*(2)*  
              invx = 1
              invy = 1
              invz = 1
              if (dmx .lt. 0.0d0) then
                 dmx = -dmx
                 invx = -1
              endif
              if (dmy .lt. 0.0d0) then
                 dmy = -dmy
                 invy = -1
              endif
              if (dmz .lt. 0.0d0) then
                 dmz = -dmz
                 invz = -1
              endif
              !*(3)*  
              alpha = al3d(dmx,dmy,dmz,c(i,j,k))
              !*(4)*  
              dmx = invx*dmx
              dmy = invy*dmy
              dmz = invz*dmz
              alpha = alpha + dmin1(0.d0,dmx) + dmin1(0.d0,dmy) + &
                   dmin1(0.d0,dmz)
              !*(5)*  
              mm1 = dmax1(a1,0.0d0)
              mm2 = 1.d0 - mm1 + dmin1(0.d0,a2)
              if (d.eq.1) then
                 dmx = dmx/(1.0d0 - a1 + a2)
                 alpha = alpha + dmx*a1
                 if (a1 .lt. 0.d0) &
                      vof1(i,j,k) = fl3d(dmx,dmy,dmz,alpha,a1  ,-a1)
                 if (a2 .gt. 0.d0) &
                      vof3(i,j,k) = fl3d(dmx,dmy,dmz,alpha,1.d0,a2)
                 vof2(i,j,k) = fl3d(dmx,dmy,dmz,alpha,mm1,mm2)
              elseif (d.eq.2) then
                 dmy = dmy/(1.0d0 - a1 + a2)
                 alpha = alpha + dmy*a1
                 if (a1 .lt. 0.d0) &
                      vof1(i,j,k) = fl3d(dmy,dmz,dmx,alpha,a1  ,-a1)
                 if (a2 .gt. 0.d0) &
                      vof3(i,j,k) = fl3d(dmy,dmz,dmx,alpha,1.d0,a2)
                 vof2(i,j,k) = fl3d(dmy,dmz,dmx,alpha,mm1,mm2)
              elseif (d.eq.3) then
                 dmz = dmz/(1.0d0 - a1 + a2)
                 alpha = alpha + dmz*a1
                 if (a1 .lt. 0.d0) &
                      vof1(i,j,k) = fl3d(dmz,dmx,dmy,alpha,a1  ,-a1)
                 if (a2 .gt. 0.d0) &
                      vof3(i,j,k) = fl3d(dmz,dmx,dmy,alpha,1.d0,a2)
                 vof2(i,j,k) = fl3d(dmz,dmx,dmy,alpha,mm1,mm2)
              endif
              !           elseif (c(i,j,k).ne.0.d0) then
              !              stop "case not allowed"
           endif
        enddo
     enddo
  enddo
  !
  ! assume that ghost layers take care of the boundary conditions. 
  ! so i-1, i+1 needs to be computed. 
  ! at least the ghost layers is-2, is-1, ie+1,ie+2  need to be there
  ! at the beginning of the subroutine, so that fluxes vof1,vof3 are computed
  ! for is-1, ie+1. 
  !    (1) new values of c and  clip it: 0. <= c <= 1.
  !    (2) apply proper boundary conditions to c
  !*(1)* 
  do k=ks,ke
     do j=js,je
        do i=is,ie
           if (d.eq.1) then
              c(i,j,k) = vof3(i-1,j,k) + vof2(i,j,k) + vof1(i+1,j,k)
           elseif (d.eq.2) then
              c(i,j,k) = vof3(i,j-1,k) + vof2(i,j,k) + vof1(i,j+1,k)
           elseif (d.eq.3) then
              c(i,j,k) = vof3(i,j,k-1) + vof2(i,j,k) + vof1(i,j,k+1)
           endif
           c(i,j,k) = dmax1(0.0d0,dmin1(1.0d0,c(i,j,k)))
        enddo
     enddo
  enddo
  !*(2)*
  call setvofbc(c)
  !***
end subroutine swpz
!
!=================================================================================================
! split 1D advection of the interface along the x,y,z (d=1,2,3) directions
!
! Following the advection method of Weymouth & Yue : Weymouth, G D, and Dick K P Yue,
! "Conservative Volume-of-Fluid Method for Free-Surface Simulations on Cartesian-Grids."
! Journal of Computational Physics 229, no. 8 (April 2010): 2853-2865. doi:10.1016/j.jcp.2009.12.018.
!=================================================================================================
!=================================================================================================
SUBROUTINE swpr(us,c,vof1,cg,vof3,dir)
!***
    USE module_grid
    USE module_flow
    USE module_vof
    use module_hello
    IMPLICIT NONE
    INTEGER :: i,j,k
    INTEGER :: invx,invy,invz,ii,jj,kk,i0,j0,k0
    INTEGER, INTENT(IN) :: dir
    REAL (8), DIMENSION(imin:imax,jmin:jmax,kmin:kmax), INTENT(IN) :: us,cg
    REAL (8), DIMENSION(imin:imax,jmin:jmax,kmin:kmax), INTENT(INOUT) :: c,vof1,vof3
    REAL(8), TARGET :: dmx,dmy,dmz,dxyz
    REAL(8), POINTER :: dm1,dm2,dm3
    REAL(8) :: EPSC,a1,a2,alpha,AL3D,FL3D
    real(8) :: mxyz(3),stencil3x3(-1:1,-1:1,-1:1)
    INTRINSIC DMAX1,DMIN1
!
  if(ng < 2) stop "wrong ng"
  ii=0; jj=0; kk=0
  if (dir == 1) then
     ii=1; dm1 => dmx;  dm2 => dmy;  dm3 => dmz 
  else if (dir == 2) then
     jj=1; dm1 => dmy;  dm2 => dmz;  dm3 => dmx 
  else if (dir == 3) then
     kk=1; dm1 => dmz;  dm2 => dmx;  dm3 => dmy 
  endif
  EPSC = 1.d-12
  dxyz = dxh(is)
  if(dyh(js).ne.dxyz.or.dzh(ks).ne.dxyz) stop "non-cubic cells"

  do k=ks-1,ke+1
     do j=js-1,je+1
        do i=is-1,ie+1
           a2 = us(i,j,k)*dt/dxyz
           a1 = us(i-ii,j-jj,k-kk)*dt/dxyz
           !  default: fluxes=0. (good also for c=0.)
           vof1(i,j,k) = 0.d0
           vof3(i,j,k) = 0.d0
           !  c = 1.
           if (c(i,j,k) == 1.0d0) then
              vof1(i,j,k) = DMAX1(-a1,0.d0)
              vof3(i,j,k) = DMAX1(a2,0.d0)
           ! 0. < c < 1.
           else if (c(i,j,k) > 0.d0) then
              ! local stencil and normal vector: |dmx|+|dmy|+|dmz| = 1.
              do i0=-1,1; do j0=-1,1; do k0=-1,1
                 stencil3x3(i0,j0,k0) = c(i+i0,j+j0,k+k0)
              enddo;enddo;enddo
              call mycs(stencil3x3,mxyz)
              dmx = mxyz(1); dmy = mxyz(2); dmz = mxyz(3)
              ! positive dmx,dmy,dmz
              invx = 1; invy = 1; invz = 1
              if (dmx < 0.d0) then
                 dmx = -dmx; invx = -1
              endif
              if (dmy < 0.d0) then
                 dmy = -dmy; invy = -1
              endif
              if (dmz < 0.0d0) then
                 dmz = -dmz; invz = -1
              endif
              ! get alpha
              alpha = AL3D(dmx,dmy,dmz,c(i,j,k))
              ! back to the original plane
              dmx = invx*dmx
              dmy = invy*dmy
              dmz = invz*dmz
              alpha = alpha + DMIN1(0.d0,dmx) + DMIN1(0.d0,dmy) + DMIN1(0.d0,dmz)
              ! Eulerian advection
                 if (a1 < 0.d0) &
                      vof1(i,j,k) = FL3D(dm1,dm2,dm3,alpha,0.d0,-a1)
                 if (a2 > 0.d0) &
                      vof3(i,j,k) = FL3D(dm1,dm2,dm3,alpha,1.d0-a2,a2)
           endif
        enddo
     enddo
  enddo
  ! assume that ghost layers take care of the boundary conditions, then 
  ! fluxes vof1,vof3 must be computed for is-1, ie+1 
  ! new clipped values of c (0. <= c <= 1)
  do k=ks,ke
     do j=js,je
        do i=is,ie
           a2 = us(i,j,k)*dt/dxyz
           a1 = us(i-ii,j-jj,k-kk)*dt/dxyz
           c(i,j,k) = c(i,j,k) - (vof3(i,j,k) - vof1(i+ii,j+jj,k+kk)) + & 
                      (vof3(i-ii,j-jj,k-kk) - vof1(i,j,k)) + cg(i,j,k)*(a2-a1);
!!$           c(i,j,k) = DMAX1(0.d0,DMIN1(1.d0,c(i,j,k)))
           if (c(i,j,k) < EPSC) then
              c(i,j,k) = 0.d0
           elseif (c(i,j,k) >  (1.d0 - EPSC)) then
              c(i,j,k) = 1.d0
           endif
        enddo
     enddo
  enddo
  ! apply proper boundary conditions to c
  call setvofbc(c)
end subroutine swpr
!=================================================================================================
!=================================================================================================
! ****** 1 ******* 2 ******* 3 ******* 4 ******* 5 ******* 6 ******* 7 *
! PROGRAM TO FIND alpha IN: m1 x1 + m2 x2 + m3 x3 = alpha,
! GIVEN m1+m2+m3=1 (all > 0) AND THE VOLUMETRIC FRACTION cc
! ****** 1 ******* 2 ******* 3 ******* 4 ******* 5 ******* 6 ******* 7 *
function al3d(b1,b2,b3,cc)
  !***
  implicit none
  real(8) m1,m2,m3,cc,b1,b2,b3,tmp,pr,ch,mm,m12
  real(8) p,p12,q,teta,cs,al3d
  real(8) untier,v1,v2,v3
  parameter (untier=1.d0/3.d0)
  intrinsic dmax1,dmin1,dsqrt,dacos,dcos
  !***  
  !     (1) order coefficients: m1<m2<m3; (2) get ranges: v1<v2<v3;
  !     (3) limit ch (0.d0 < ch < 0.5d0); (4) calculate alpha
  !*(1)* 
  m1 = dmin1(b1,b2)
  m3 = dmax1(b1,b2)
  m2 = b3
  if (m2 .lt. m1) then
     tmp = m1
     m1 = m2
     m2 = tmp
  else if (m2 .gt. m3) then
     tmp = m3
     m3 = m2
     m2 = tmp
  endif
  !*(2)*
  m12 = m1 + m2 
  pr  = DMAX1(6.d0*m1*m2*m3,1.d-50)
  V1  = m1*m1*m1/pr
  V2  = V1 + 0.5d0*(m2-m1)/m3
  if (m3 .LT. m12) then
     mm = m3
     V3 = (m3*m3*(3.d0*m12-m3) + m1*m1*(m1-3.d0*m3) +&
          m2*m2*(m2-3.d0*m3))/pr
  else
     mm = m12
     V3 = 0.5d0*mm/m3
  endif
  !*(3)*
  ch = DMIN1(cc,1.d0-cc)
  !*(4)*      
  if (ch .LT. V1) then
     !***         AL3D = cbrt(pr*ch)
     AL3D = (pr*ch)**UNTIER
  else if (ch .LT. V2) then
     AL3D = 0.5d0*(m1 + DSQRT(m1*m1 + 8.d0*m2*m3*(ch-V1)))
  else if (ch .LT. V3) then
     p = 2.d0*m1*m2
     q = 1.5d0*m1*m2*(m12 - 2.d0*m3*ch)
     p12 = DSQRT(p)
     teta = DACOS(q/(p*p12))/3.d0
     cs = DCOS(teta)
     AL3D = p12*(DSQRT(3.d0*(1.d0-cs*cs)) - cs) + m12
  else if (m12 .LT. m3) then
     AL3D = m3*ch + 0.5d0*mm
  else 
     p = m1*(m2+m3) + m2*m3 - 0.25d0
     q = 1.5d0*m1*m2*m3*(0.5d0-ch)
     p12 = DSQRT(p)
     teta = DACOS(q/(p*p12))/3.0
     cs = DCOS(teta)
     AL3D = p12*(DSQRT(3.d0*(1.d0-cs*cs)) - cs) + 0.5d0
  endif

  if (cc .GT. 0.5d0)  AL3D = 1.d0 - AL3D
  !***
  return
end function al3d
! ****** 1 ******* 2 ******* 3 ******* 4 ******* 5 ******* 6 ******* 7 *
! PROGRAM TO FIND THE "CUT VOLUME" V0 GIVEN r0, dr0 AND
! m1 x1 + m2 x2 + m3 x3 = alpha
! ****** 1 ******* 2 ******* 3 ******* 4 ******* 5 ******* 6 ******* 7 *
function fl3d(m1,m2,m3,alpha,r0,dr0)
  !***
  implicit none
  real(8) m1,m2,m3,alpha,r0,dr0,fl3D
  real(8) al,al0,n1,n2,n3,b1,b2,b3,b12,bm,tmp,pr
  INTRINSIC DMAX1,DMIN1,DABS
  !***
  !     (1) move origin to r0 along r ;  (2) reflect parallelepiped;
  !     (3) limit alpha (0<= al0 <=0.5); (4) order coefficients: b1<b2<b3;
  !     (5) calculate volume (NOTE: it is assumed:s0=t0=0; ds0=dt0=1.)
  !*(1)*
  al = alpha - m1*r0
  !*(2)*
  al = al + DMAX1(0.d0,-m1*dr0)+DMAX1(0.d0,-m2)+DMAX1(0.d0,-m3)
  tmp = DABS(m1)*dr0 + DABS(m2) + DABS(m3)
  n1 = DABS(m1)/tmp
  n2 = DABS(m2)/tmp
  n3 = DABS(m3)/tmp
  al = DMAX1(0.d0,DMIN1(1.d0,al/tmp))
  !*(3)*
  al0 = DMIN1(al,1.d0-al)
  !*(4)*
  b1 = DMIN1(n1*dr0,n2)
  b3 = DMAX1(n1*dr0,n2)
  b2 = n3
  if (b2 .LT. b1) then
     tmp = b1
     b1 = b2
     b2 = tmp
  else if (b2 .GT. b3) then
     tmp = b3
     b3 = b2
     b2 = tmp
  endif
  b12 = b1 + b2
  bm = DMIN1(b12,b3)
  pr = DMAX1(6.d0*b1*b2*b3,1.0d-50)
  !*5*     
  if (al0 .LT. b1) then
     tmp = al0*al0*al0/pr
  else if (al0 .LT. b2) then
     tmp = 0.5d0*al0*(al0-b1)/(b2*b3) +  b1*b1*b1/pr
  else if (al0 .LT. bm) then
     tmp = (al0*al0*(3.d0*b12-al0) + b1*b1*(b1-3.d0*al0) +&
          b2*b2*(b2-3.d0*al0))/pr
  else if (b12 .LT. b3) then
     tmp = (al0 - 0.5d0*bm)/b3
  else
     tmp = (al0*al0*(3.d0-2.d0*al0) + b1*b1*(b1-3.d0*al0) +&
          b2*b2*(b2-3.d0*al0) + b3*b3*(b3-3.d0*al0))/pr
  endif

  if (al .LE. 0.5d0) then
     FL3D = tmp*dr0
  else
     FL3D = (1.d0-tmp)*dr0
  endif
  !***  
  return
end function fl3d
! ****** 1 ******* 2 ******* 3 ******* 4 ******* 5 ******* 6 ******* 7 *
!   Converts a level-set field into a VOF field
!   On entry:  cc: an allocated array, ls: the level-set function.
!   On output: cc: becomes the volume fraction, ls: untouched.
! ****** 1 ******* 2 ******* 3 ******* 4 ******* 5 ******* 6 ******* 7 *
subroutine levelset2vof(ls,cc,nx,ny,nz)
!  use module_BC
  implicit none
  include 'mpif.h'
  integer nx,ny,nz
  real(8) cc(nx,ny,nz),ls(nx,ny,nz)
  real(8) zero, one, norml1
  real(8) mm1,mm2,mm3,mx,my,mz,alpha
  real(8) fl3d
  integer i,j,k
  integer :: req(48),sta(MPI_STATUS_SIZE,48)
  integer :: ngh=2, ierr


  zero=0.d0
  one=1.d0
  do k=2,nz-1
     do j=2,ny-1
        do i=2,nx-1
           !***
           !     (1) normal vector: mx,my,mz; (2) mx,my,mz>0. and mx+my+mz = 1.;
           !     (3) shift alpha to origin;   (4) get volume from alpha.  
           !***

           mm1 = ls(i-1,j-1,k-1)+ls(i-1,j-1,k+1)+ls(i-1,j+1,k-1) &
                +ls(i-1,j+1,k+1)+2.0d0*(ls(i-1,j-1,k)+ls(i-1,j+1,k) &
                +ls(i-1,j,k-1)+ls(i-1,j,k+1))+4.0d0*ls(i-1,j,k)
           mm2 = ls(i+1,j-1,k-1)+ls(i+1,j-1,k+1)+ls(i+1,j+1,k-1) &
                +ls(i+1,j+1,k+1)+2.0d0*(ls(i+1,j-1,k)+ls(i+1,j+1,k) &
                +ls(i+1,j,k-1)+ls(i+1,j,k+1))+4.0d0*ls(i+1,j,k)
           mx = (mm1 - mm2)/32.d0

           mm1 = ls(i-1,j-1,k-1)+ls(i-1,j-1,k+1)+ls(i+1,j-1,k-1) &
                +ls(i+1,j-1,k+1)+2.0d0*(ls(i-1,j-1,k)+ls(i+1,j-1,k) &
                +ls(i,j-1,k-1)+ls(i,j-1,k+1))+4.0d0*ls(i,j-1,k)
           mm2 = ls(i-1,j+1,k-1)+ls(i-1,j+1,k+1)+ls(i+1,j+1,k-1) &
                +ls(i+1,j+1,k+1)+2.0d0*(ls(i-1,j+1,k)+ls(i+1,j+1,k) &
                +ls(i,j+1,k-1)+ls(i,j+1,k+1))+4.0d0*ls(i,j+1,k)
           my = (mm1 - mm2)/32.d0

           mm1 = ls(i-1,j-1,k-1)+ls(i-1,j+1,k-1)+ls(i+1,j-1,k-1) &
                +ls(i+1,j+1,k-1)+2.0d0*(ls(i-1,j,k-1)+ls(i+1,j,k-1) &
                +ls(i,j-1,k-1)+ls(i,j+1,k-1))+4.0d0*ls(i,j,k-1)
           mm2 = ls(i-1,j-1,k+1)+ls(i-1,j+1,k+1)+ls(i+1,j-1,k+1) &
                +ls(i+1,j+1,k+1)+2.0d0*(ls(i-1,j,k+1)+ls(i+1,j,k+1) &
                +ls(i,j-1,k+1)+ls(i,j+1,k+1))+4.0d0*ls(i,j,k+1)
           mz = (mm1 - mm2)/32.d0
           !***
           !     *(2)*  
           !***
           mx = dabs(mx)
           my = dabs(my)
           mz = dabs(mz)
           norml1 = mx+my+mz
           mx = mx/norml1
           my = my/norml1
           mz = mz/norml1

           alpha = ls(i,j,k)/norml1
           !***
           !     *(3)*  
           !***
           alpha = alpha + 0.5d0
           !***
           !     *(4)*  
           !***
           if(alpha.ge.1.d0) then 
              cc(i,j,k) = 1.d0
           else if (alpha.le.0.d0) then
              cc(i,j,k) = 0.d0
           else 
              cc(i,j,k) = fl3d(mx,my,mz,alpha,zero,one)
           end if
        enddo
     enddo
  enddo
  return
end subroutine levelset2vof
!
!
!
! *-----------------------------------------------------* 
! *  MYC - Mixed Youngs and Central Scheme              *
! *-----------------------------------------------------*
! 
!
!Known problems: the index (1,1,1), i.e. the central cell
!in the block, never occurs: neither in the central scheme
!nor in Youngs' method. Therefore an isolated droplet will have
!a normal with all components to zero. I took care of the
!division-by-zero issue, but not of this one.
!
!Ruben
!
!
! Translated into f90 by Stephane Z.
!
subroutine mycs(c,mxyz)
  !***
  implicit none
  real(8) c(0:2,0:2,0:2)
  real(8) mxyz(0:2)
  real(8) m1,m2,m(0:3,0:2),t0,t1,t2
  integer cn
  real(8) :: NOT_ZERO=1.e-30

  ! write the plane as: sgn(mx) X =  my Y +  mz Z + alpha 
  !                           m00 X = m01 Y + m02 Z + alpha 

  m1 = c(0,1,0) + c(0,1,2) + c(0,0,1) + c(0,2,1) + &
       c(0,1,1)
  m2 = c(2,1,0) + c(2,1,2) + c(2,0,1) + c(2,2,1) + &
       c(2,1,1)

  if(m1>m2) then
     m(0,0) = 1.
  else
     m(0,0) = -1.
  end if

  m1 = c(0,0,1)+ c(2,0,1)+ c(1,0,1)
  m2 = c(0,2,1)+ c(2,2,1)+ c(1,2,1)
  m(0,1) = 0.5*(m1-m2)

  m1 = c(0,1,0)+ c(2,1,0)+ c(1,1,0)
  m2 = c(0,1,2)+ c(2,1,2)+ c(1,1,2)
  m(0,2) = 0.5*(m1-m2)

  ! write the plane as: sgn(my) Y =  mx X +  mz Z + alpha, 
  !                          m11 Y = m10 X + m12 Z + alpha.

  m1 = c(0,0,1) + c(0,2,1) + c(0,1,1)
  m2 = c(2,0,1) + c(2,2,1) + c(2,1,1)
  m(1,0) = 0.5*(m1-m2)

  m1 = c(1,0,0) + c(1,0,2) + c(2,0,1) + c(0,0,1) +&
       c(1,0,1)
  m2 = c(1,2,0) + c(1,2,2) + c(2,2,1) + c(0,2,1) +&
       c(1,2,1)


  if(m1>m2) then
     m(1,1) = 1.
  else
     m(1,1) = -1.
  end if

  m1 = c(1,0,0)+ c(1,1,0)+ c(1,2,0)
  m2 = c(1,0,2)+ c(1,1,2)+ c(1,2,2)
  m(1,2) = 0.5*(m1-m2)

  ! write the plane as: sgn(mz) Z =  mx X +  my Y + alpha 
  !                          m22 Z = m20 X + m21 Y + alpha

  m1 = c(0,1,0)+ c(0,1,2)+ c(0,1,1)
  m2 = c(2,1,0)+ c(2,1,2)+ c(2,1,1)
  m(2,0) = 0.5*(m1-m2)

  m1 = c(1,0,0)+ c(1,0,2)+ c(1,0,1)
  m2 = c(1,2,0)+ c(1,2,2)+ c(1,2,1)
  m(2,1) = 0.5*(m1-m2)

  m1 = c(0,1,0) + c(2,1,0) + c(1,0,0) + c(1,2,0) +&
       c(1,1,0)
  m2 = c(0,1,2) + c(2,1,2) + c(1,0,2) + c(1,2,2) +&
       c(1,1,2)

  if(m1>m2) then
     m(2,2) = 1.
  else
     m(2,2) = -1.
  end if

  ! normalize each set (mx,my,mz): |mx|+|my|+|mz| = 1

  t0 = DABS(m(0,0)) + DABS(m(0,1)) + DABS(m(0,2))
  m(0,0) = m(0,0)/t0
  m(0,1) = m(0,1)/t0
  m(0,2) = m(0,2)/t0

  t0 = DABS(m(1,0)) + DABS(m(1,1)) + DABS(m(1,2))
  m(1,0) = m(1,0)/t0
  m(1,1) = m(1,1)/t0
  m(1,2) = m(1,2)/t0

  t0 = DABS(m(2,0)) + DABS(m(2,1)) + DABS(m(2,2))
  m(2,0) = m(2,0)/t0
  m(2,1) = m(2,1)/t0
  m(2,2) = m(2,2)/t0

  ! choose among the three central schemes */ 
  t0 = DABS(m(0,0))
  t1 = DABS(m(1,1))
  t2 = DABS(m(2,2))

  cn = 0
  if (t1 > t0) then
    t0 = t1
    cn = 1
  endif

  if (t2 > t0) cn = 2

  ! Youngs-CIAM scheme */  

  m1 = c(0,0,0) + c(0,2,0) + c(0,0,2) + c(0,2,2) +&
       2.*(c(0,0,1) + c(0,2,1) + c(0,1,0) + c(0,1,2)) +&
       4.*c(0,1,1)
  m2 = c(2,0,0) + c(2,2,0) + c(2,0,2) + c(2,2,2) +&
       2.*(c(2,0,1) + c(2,2,1) + c(2,1,0) + c(2,1,2)) +&
       4.*c(2,1,1)
  m(3,0) = m1-m2

  m1 = c(0,0,0) + c(0,0,2) + c(2,0,0) + c(2,0,2) +&
       2.*( c(0,0,1) + c(2,0,1) + c(1,0,0) + c(1,0,2)) +&
       4.*c(1,0,1)
  m2 = c(0,2,0) + c(0,2,2) + c(2,2,0) + c(2,2,2) +&
       2.*(c(0,2,1) + c(2,2,1) + c(1,2,0) + c(1,2,2)) +&
       4.*c(1,2,1)
  m(3,1) = m1-m2

  m1 = c(0,0,0) + c(0,2,0) + c(2,0,0) + c(2,2,0) +&
       2.*(c(0,1,0) + c(2,1,0) + c(1,0,0) + c(1,2,0)) +&
       4.*c(1,1,0)
  m2 = c(0,0,2) + c(0,2,2) + c(2,0,2) + c(2,2,2) +&
       2.*(c(0,1,2) + c(2,1,2) + c(1,0,2) + c(1,2,2)) +&
       4.*c(1,1,2)
  m(3,2) = m1-m2

  ! normalize the set (mx,my,mz): |mx|+|my|+|mz| = 1 

  t0 = DABS(m(3,0)) + DABS(m(3,1)) + DABS(m(3,2)) + NOT_ZERO
  m(3,0) = m(3,0)/t0
  m(3,1) = m(3,1)/t0
  m(3,2) = m(3,2)/t0

  ! choose between the previous choice and Youngs-CIAM 
  t0 = DABS (m(3,0))
  t1 = DABS (m(3,1))
  t2 = DABS (m(3,2))
  if (t1 > t0)  t0 = t1
  if (t2 > t0)  t0 = t2

  if (DABS(m(cn,cn)) > t0)  cn = 3

  ! components of the normal vector */
  mxyz(0) = m(cn,0)
  mxyz(1) = m(cn,1)
  mxyz(2) = m(cn,2)

  return 
  end subroutine mycs
