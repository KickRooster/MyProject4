// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "Animation/AnimInstance.h"
#include "SandboxCharacterBase.generated.h"

class UInputAction;
struct FInputActionValue;

/**
 * Base C++ class for SandboxCharacter_CMC blueprint.
 * Provides Wall Jump, Coyote Time, and Double Jump functionality.
 */
UCLASS()
class MYPROJECT4_API ASandboxCharacterBase : public ACharacter
{
	GENERATED_BODY()

public:
	ASandboxCharacterBase();

protected:
	// ---- Wall Jump ----

	/** Time to disable player movement input after a wall jump, so the
	 *  launch velocity is not immediately overridden by player input.
	 *  During this window the character naturally rotates toward its velocity. */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Side Scrolling|Wall Jump")
	float WallJumpInputLockout = 0.3f;

	/** Distance to trace ahead of the character for wall jumps */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Side Scrolling|Wall Jump")
	float WallJumpTraceDistance = 50.0f;

	/** Horizontal impulse to apply to the character during wall jumps */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Side Scrolling|Wall Jump")
	float WallJumpHorizontalImpulse = 500.0f;

	/** Multiplies the jump Z velocity for wall jumps */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Side Scrolling|Wall Jump")
	float WallJumpVerticalMultiplier = 1.4f;

	/** Wall jump lockout timer */
	FTimerHandle WallJumpTimer;

	/** If true, player movement input is currently locked out (wall jump in progress) */
	UPROPERTY(BlueprintReadOnly, Category="Side Scrolling|Wall Jump")
	bool bWallJumpInputLocked = false;

	// ---- Coyote Time ----

	/** Last recorded time when this character started falling */
	float LastFallTime = 0.0f;

	/** Max coyote time window (seconds) */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Side Scrolling|Coyote Time", meta = (ClampMin = 0, ClampMax = 5, Units = "s"))
	float MaxCoyoteTime = 0.16f;

	// ---- Double Jump ----

	/** If true, this character has already double jumped */
	UPROPERTY(BlueprintReadOnly, Category="Side Scrolling|Jump")
	bool bHasDoubleJumped = false;

	/** Cached horizontal movement input for wall jump direction */
	UPROPERTY(BlueprintReadWrite, Category="Side Scrolling|Input")
	float CachedHorizontalInput = 0.0f;

	// ---- Melee Attack ----

	/** AnimMontage to play for combo attacks (assign in Blueprint defaults) */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Combat|Combo")
	TObjectPtr<UAnimMontage> ComboAttackMontage;

	/** Section names in the ComboAttackMontage for each combo stage */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Combat|Combo")
	TArray<FName> ComboSectionNames;

	/** Max time tolerance for buffered combo inputs */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Combat|Combo", meta=(ClampMin=0, ClampMax=5, Units="s"))
	float ComboInputCacheTolerance = 0.45f;

	/** Input Action for combo attack (assign in Blueprint defaults) */
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Combat|Input")
	TObjectPtr<UInputAction> ComboAttackAction;

	/** If true, an attack montage is currently playing */
	UPROPERTY(BlueprintReadOnly, Category="Combat")
	bool bIsAttacking = false;

	/** Current combo stage index */
	int32 ComboCount = 0;

	/** Time the attack button was last pressed (for input buffering) */
	float CachedAttackInputTime = 0.0f;

	/** Delegate bound to montage end */
	FOnMontageEnded OnAttackMontageEnded;

public:
	// ---- Blueprint-callable functions ----

	/**
	 * Attempts a wall jump. Call this from the blueprint's jump logic.
	 * Returns true if a wall jump was performed.
	 */
	UFUNCTION(BlueprintCallable, Category="Side Scrolling|Wall Jump")
	bool TryWallJump();

	/**
	 * Advanced jump: tries wall jump first, then coyote time, then double jump.
	 * Call this instead of the default Jump() for full 2D platformer behavior.
	 */
	UFUNCTION(BlueprintCallable, Category="Side Scrolling|Jump")
	void MultiJump();

	/** Returns true if the character has just double jumped */
	UFUNCTION(BlueprintPure, Category="Side Scrolling")
	bool HasDoubleJumped() const { return bHasDoubleJumped; }

	/** Returns true if wall jump input lockout is active.
	 *  Blueprint should check this to suppress movement input AND rotation. */
	UFUNCTION(BlueprintPure, Category="Side Scrolling")
	bool IsWallJumpInputLocked() const { return bWallJumpInputLocked; }

	/** Alias — used by UpdateRotation_PreCMC blueprint to skip rotation updates */
	UFUNCTION(BlueprintPure, Category="Side Scrolling")
	bool HasWallJumped() const { return bWallJumpInputLocked; }

	/** Returns true if an attack montage is currently playing */
	UFUNCTION(BlueprintPure, Category="Combat")
	bool IsAttacking() const { return bIsAttacking; }

protected:
	/** Called when character lands */
	virtual void Landed(const FHitResult& Hit) override;

	/** Track when falling starts for coyote time */
	virtual void OnMovementModeChanged(EMovementMode PrevMovementMode, uint8 PreviousCustomMode = 0) override;

	/** Cleanup timers */
	virtual void EndPlay(EEndPlayReason::Type EndPlayReason) override;

	/** Register input bindings */
	virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;

	// ---- Attack internals ----

	/** Starts or continues a combo attack */
	void ComboAttack();

	/** Called when the attack montage ends */
	void AttackMontageEnded(UAnimMontage* Montage, bool bInterrupted);

	/** Input callback for combo attack button */
	void OnComboAttackPressed();

private:
	/** Resets wall jump lockout. Called from timer */
	void ResetWallJump();
};