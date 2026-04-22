// Copyright Epic Games, Inc. All Rights Reserved.

#include "SandboxCharacterBase.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Components/CapsuleComponent.h"
#include "Kismet/KismetMathLibrary.h"
#include "EnhancedInputComponent.h"
#include "TimerManager.h"
#include "Engine/World.h"

ASandboxCharacterBase::ASandboxCharacterBase()
{
	// Enable double jump (normal + double + wall = 3)
	JumpMaxCount = 3;

	// Bind the attack montage ended delegate
	OnAttackMontageEnded.BindUObject(this, &ASandboxCharacterBase::AttackMontageEnded);
}

void ASandboxCharacterBase::EndPlay(EEndPlayReason::Type EndPlayReason)
{
	Super::EndPlay(EndPlayReason);
	GetWorld()->GetTimerManager().ClearTimer(WallJumpTimer);
}

void ASandboxCharacterBase::Landed(const FHitResult& Hit)
{
	Super::Landed(Hit);
	bHasDoubleJumped = false;
	bWallJumpInputLocked = false;

	// Ensure CMC auto-rotation is restored on landing
	GetCharacterMovement()->bOrientRotationToMovement = true;
}

void ASandboxCharacterBase::OnMovementModeChanged(EMovementMode PrevMovementMode, uint8 PreviousCustomMode)
{
	Super::OnMovementModeChanged(PrevMovementMode, PreviousCustomMode);

	if (GetCharacterMovement()->MovementMode == EMovementMode::MOVE_Falling)
	{
		LastFallTime = GetWorld()->GetTimeSeconds();
	}
}

bool ASandboxCharacterBase::TryWallJump()
{
	// Must be in the air and have horizontal input, and not already locked out
	if (!GetCharacterMovement()->IsFalling() || bWallJumpInputLocked || FMath::IsNearlyZero(CachedHorizontalInput))
	{
		return false;
	}

	// Trace ahead of the character for walls
	FHitResult OutHit;
	const FVector Start = GetActorLocation();
	const FVector TraceDir = GetActorForwardVector();
	const FVector End = Start + (TraceDir * WallJumpTraceDistance);

	FCollisionQueryParams QueryParams;
	QueryParams.AddIgnoredActor(this);

	GetWorld()->LineTraceSingleByChannel(OutHit, Start, End, ECC_Visibility, QueryParams);

	if (!OutHit.bBlockingHit)
	{
		return false;
	}

	// Calculate the bounce impulse (away from wall + upward)
	const FVector BounceDir = OutHit.ImpactNormal;
	FVector WallJumpImpulse = BounceDir * WallJumpHorizontalImpulse;
	WallJumpImpulse.Z = GetCharacterMovement()->JumpZVelocity * WallJumpVerticalMultiplier;

	// Disable CMC auto-rotation so it doesn't interpolate over our instant rotation
	GetCharacterMovement()->bOrientRotationToMovement = false;

	// Instantly face the bounce direction
	const FRotator BounceRot = FRotator(0.0f, UKismetMathLibrary::MakeRotFromX(BounceDir).Yaw, 0.0f);
	SetActorRotation(BounceRot);

	// Launch the character away from the wall
	LaunchCharacter(WallJumpImpulse, true, true);

	// Lock out player movement input so that key presses don't immediately
	// override the launch velocity and cancel the natural rotation.
	bWallJumpInputLocked = true;

	UE_LOG(LogTemp, Warning, TEXT("=== WALL JUMP! Normal: %s, Impulse: %s ==="),
		*OutHit.ImpactNormal.ToString(), *WallJumpImpulse.ToString());

	// Schedule lockout reset
	GetWorld()->GetTimerManager().SetTimer(
		WallJumpTimer, this, &ASandboxCharacterBase::ResetWallJump,
		WallJumpInputLockout, false
	);

	return true;
}

void ASandboxCharacterBase::MultiJump()
{
	// If grounded, just do a normal jump
	if (!GetCharacterMovement()->IsFalling())
	{
		Jump();
		return;
	}

	// Try wall jump first
	if (TryWallJump())
	{
		return;
	}

	// Coyote time: allow a regular jump shortly after falling off a ledge
	if (GetWorld()->GetTimeSeconds() - LastFallTime < MaxCoyoteTime)
	{
		Jump();
		return;
	}

	// Double jump
	if (!bHasDoubleJumped)
	{
		bHasDoubleJumped = true;
		Jump();
	}
}

void ASandboxCharacterBase::ResetWallJump()
{
	bWallJumpInputLocked = false;

	// Restore CMC auto-rotation now that the wall jump lockout is over
	GetCharacterMovement()->bOrientRotationToMovement = true;
}

// ============================================================
//  Melee Attack
// ============================================================

void ASandboxCharacterBase::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
	Super::SetupPlayerInputComponent(PlayerInputComponent);

	if (UEnhancedInputComponent* EIC = Cast<UEnhancedInputComponent>(PlayerInputComponent))
	{
		if (ComboAttackAction)
		{
			EIC->BindAction(ComboAttackAction, ETriggerEvent::Started, this, &ASandboxCharacterBase::OnComboAttackPressed);
		}
	}
}

void ASandboxCharacterBase::OnComboAttackPressed()
{
	// If already attacking, buffer the input for combo continuation
	if (bIsAttacking)
	{
		CachedAttackInputTime = GetWorld()->GetTimeSeconds();
		return;
	}

	// Start a fresh combo
	ComboAttack();
}

void ASandboxCharacterBase::ComboAttack()
{
	bIsAttacking = true;
	ComboCount = 0;

	UAnimInstance* AnimInstance = GetMesh()->GetAnimInstance();
	if (!AnimInstance || !ComboAttackMontage)
	{
		bIsAttacking = false;
		return;
	}

	const float MontageLength = AnimInstance->Montage_Play(ComboAttackMontage, 1.0f, EMontagePlayReturnType::MontageLength, 0.0f, true);

	if (MontageLength > 0.0f)
	{
		// Subscribe to montage end so we can reset state
		AnimInstance->Montage_SetEndDelegate(OnAttackMontageEnded, ComboAttackMontage);
	}
	else
	{
		bIsAttacking = false;
	}

	UE_LOG(LogTemp, Log, TEXT("=== COMBO ATTACK START (Section 0) ==="));
}

void ASandboxCharacterBase::AttackMontageEnded(UAnimMontage* Montage, bool bInterrupted)
{
	bIsAttacking = false;

	// If the player pressed attack again during the montage, start a new combo
	if (!bInterrupted && (GetWorld()->GetTimeSeconds() - CachedAttackInputTime <= ComboInputCacheTolerance))
	{
		ComboAttack();
	}

	UE_LOG(LogTemp, Log, TEXT("=== ATTACK MONTAGE ENDED (Interrupted: %s) ==="),
		bInterrupted ? TEXT("Yes") : TEXT("No"));
}
