// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "MyProject4GameMode.generated.h"

/**
 *  Simple GameMode for a third person game
 */
UCLASS(abstract)
class AMyProject4GameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	
	/** Constructor */
	AMyProject4GameMode();
};



